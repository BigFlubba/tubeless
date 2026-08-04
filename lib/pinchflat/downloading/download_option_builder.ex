defmodule Pinchflat.Downloading.DownloadOptionBuilder do
  @moduledoc """
  Builds the options for yt-dlp to download media based on the given media profile.
  """

  alias Pinchflat.Repo
  alias Pinchflat.Sources
  alias Pinchflat.Sources.Source
  alias Pinchflat.Media.MediaItem
  alias Pinchflat.Profiles.MediaProfile
  alias Pinchflat.Downloading.OutputPathBuilder
  alias Pinchflat.Downloading.QualityOptionBuilder

  alias Pinchflat.Utils.FilesystemUtils, as: FSUtils

  @doc """
  Builds the options for yt-dlp to download media based on the given media's profile.

  Returns {:ok, [Keyword.t()]}
  """
  def build(%MediaItem{} = media_item_with_preloads, override_opts \\ []) do
    media_profile = media_item_with_preloads.source.media_profile

    built_options =
      default_options(override_opts) ++
        subtitle_options(media_profile) ++
        thumbnail_options(media_item_with_preloads) ++
        metadata_options(media_profile) ++
        quality_options(media_profile) ++
        sponsorblock_options(media_profile) ++
        output_options(media_item_with_preloads) ++
        config_file_options(media_item_with_preloads)

    {:ok, built_options}
  end

  @doc """
  Builds the output path for yt-dlp to download media based on the given source's
  or media_item's media profile. Uses the source's override output path template if it exists.

  Accepts a %MediaItem{} or %Source{} struct. If a %Source{} struct is passed, it
  will use a default %MediaItem{} struct with the given source. Optionally accepts
  a map of template options that override the defaults (and any custom variables
  with the same name) when rendering the template.

  Returns binary()
  """
  def build_output_path_for(record, additional_template_options \\ %{})

  def build_output_path_for(%Source{} = source_with_preloads, additional_template_options) do
    build_output_path_for(%MediaItem{source: source_with_preloads}, additional_template_options)
  end

  def build_output_path_for(%MediaItem{} = media_item_with_preloads, additional_template_options) do
    output_path_template = Sources.output_path_template(media_item_with_preloads.source)

    build_output_path(output_path_template, media_item_with_preloads, additional_template_options)
  end

  @doc """
  Builds the quality options for yt-dlp to download media based on the given source's
  or media_item's media profile. Useful for helping predict final filepath of downloaded
  media.

  returns [Keyword.t()]
  """
  def build_quality_options_for(%Source{} = source_with_preloads) do
    build_quality_options_for(%MediaItem{source: source_with_preloads})
  end

  def build_quality_options_for(%MediaItem{} = media_item_with_preloads) do
    media_profile = media_item_with_preloads.source.media_profile

    quality_options(media_profile)
  end

  @doc """
  Builds the subset of yt-dlp options a media profile determines entirely on its
  own — everything that doesn't depend on a specific media item (so no output
  paths, thumbnail destination, or per-source config file).

  Powers the read-only "Effective yt-dlp options" preview on the media profile
  page, so what the preview shows can't drift from what a real download passes.

  Returns [Keyword.t() | atom()]
  """
  def build_profile_options(%MediaProfile{} = media_profile) do
    subtitle_options(media_profile) ++
      profile_thumbnail_options(media_profile) ++
      metadata_options(media_profile) ++
      quality_options(media_profile) ++
      sponsorblock_options(media_profile)
  end

  defp default_options(override_opts) do
    overwrite_behaviour = Keyword.get(override_opts, :overwrite_behaviour, :force_overwrites)

    [
      :no_progress,
      overwrite_behaviour,
      # This makes the date metadata conform to what jellyfin expects
      parse_metadata: "%(upload_date>%Y-%m-%d)s:(?P<meta_date>.+)"
    ]
  end

  defp subtitle_options(media_profile) do
    mapped_struct = Map.from_struct(media_profile)

    Enum.reduce(mapped_struct, [], fn attr, acc ->
      case {attr, media_profile} do
        {{:download_subs, true}, _} ->
          # Force SRT for now - MAY provide as an option in the future
          acc ++ [:write_subs, convert_subs: "srt"]

        {{:download_auto_subs, true}, %{download_subs: true}} ->
          acc ++ [:write_auto_subs]

        {{:download_auto_subs, true}, %{embed_subs: true}} ->
          acc ++ [:write_auto_subs]

        {{:embed_subs, true}, %{preferred_resolution: pr}} when pr != :audio ->
          acc ++ [:embed_subs]

        {{:sub_langs, sub_langs}, %{download_subs: true}} ->
          acc ++ [sub_langs: sub_langs]

        {{:sub_langs, sub_langs}, %{embed_subs: true}} ->
          acc ++ [sub_langs: sub_langs]

        _ ->
          acc
      end
    end)
  end

  # The profile decides *whether* to write/embed a thumbnail and what format it
  # ends up in; only the save location needs the media item. Splitting it that way
  # lets `build_profile_options/1` report the same flags a download really passes
  # instead of keeping a second, drift-prone list of them.
  defp thumbnail_options(media_item_with_preloads) do
    media_profile = media_item_with_preloads.source.media_profile

    Enum.flat_map(profile_thumbnail_options(media_profile), fn
      :write_thumbnail ->
        [:write_thumbnail, output: "thumbnail:#{determine_thumbnail_location(media_item_with_preloads)}"]

      option ->
        [option]
    end)
  end

  defp profile_thumbnail_options(media_profile) do
    mapped_struct = Map.from_struct(media_profile)

    Enum.reduce(mapped_struct, [], fn attr, acc ->
      case attr do
        {:download_thumbnail, true} -> acc ++ [:write_thumbnail, convert_thumbnail: "jpg"]
        {:embed_thumbnail, true} -> acc ++ [:embed_thumbnail, convert_thumbnail: "jpg"]
        _ -> acc
      end
    end)
  end

  defp metadata_options(media_profile) do
    mapped_struct = Map.from_struct(media_profile)

    Enum.reduce(mapped_struct, [], fn attr, acc ->
      case attr do
        {:download_metadata, true} -> acc ++ [:write_info_json, :clean_info_json]
        {:embed_metadata, true} -> acc ++ [:embed_metadata]
        _ -> acc
      end
    end)
  end

  defp quality_options(media_profile) do
    QualityOptionBuilder.build(media_profile)
  end

  # yt-dlp accepts both flags in one invocation, so each category can be
  # removed or marked as a chapter independently
  defp sponsorblock_options(media_profile) do
    [
      sponsorblock_remove: Enum.join(media_profile.sponsorblock_remove_categories, ","),
      sponsorblock_mark: Enum.join(media_profile.sponsorblock_mark_categories, ",")
    ]
    |> Enum.reject(fn {_flag, categories} -> categories == "" end)
  end

  # This is put here instead of the CommandRunner module because it should only
  # be applied to downloading - if it were in CommandRunner it would apply to
  # all yt-dlp commands (like indexing)
  defp config_file_options(media_item) do
    base_dir = Path.join(Application.get_env(:pinchflat, :extras_directory), "yt-dlp-configs")
    # Ordered by priority - the first file has the highest priority
    filenames = [
      "media-item-#{media_item.id}-config.txt",
      "source-#{media_item.source_id}-config.txt",
      "media-profile-#{media_item.source.media_profile_id}-config.txt",
      "base-config.txt"
    ]

    config_filepaths =
      Enum.reduce(filenames, [], fn filename, acc ->
        filepath = Path.join(base_dir, filename)

        if FSUtils.exists_and_nonempty?(filepath) do
          [filepath | acc]
        else
          acc
        end
      end)

    Enum.map(config_filepaths, fn filepath -> {:config_locations, filepath} end)
  end

  defp output_options(media_item_with_preloads) do
    [
      output: build_output_path_for(media_item_with_preloads)
    ]
  end

  defp build_output_path(string, media_item_with_preloads, additional_template_options) do
    additional_options_map = Map.merge(output_options_map(media_item_with_preloads), additional_template_options)
    {:ok, output_path} = OutputPathBuilder.build(string, additional_options_map)

    Path.join(base_directory(media_item_with_preloads.source), output_path)
  end

  defp output_options_map(media_item_with_preloads) do
    source = media_item_with_preloads.source

    %{
      "media_item_id" => to_string(media_item_with_preloads.id),
      "source_id" => to_string(source.id),
      "media_profile_id" => to_string(source.media_profile_id),
      "source_custom_name" => source.custom_name,
      # to_string guards the template parser against a nil slug (e.g. a source
      # created before slugs existed and not yet backfilled) - a nil here would
      # crash OutputPathBuilder for every source, podcast or not
      "source_slug" => to_string(source.slug),
      "source_collection_id" => source.collection_id,
      "source_collection_name" => source.collection_name,
      "source_collection_type" => to_string(source.collection_type),
      "media_playlist_index" => pad_int(media_item_with_preloads.playlist_index),
      "media_upload_date_index" => pad_int(media_item_with_preloads.upload_date_index)
    }
  end

  # The thumbnail must share the media file's basename (differing only in
  # extension) for media center apps to pick it up as the episode thumbnail -
  # Plex in particular only matches an exactly-named sidecar image
  defp determine_thumbnail_location(media_item_with_preloads) do
    build_output_path_for(media_item_with_preloads)
  end

  defp pad_int(integer, count \\ 2, padding \\ "0") do
    integer
    |> to_string()
    |> String.pad_leading(count, padding)
  end

  # Podcast sources download straight into the servable podcast library (served
  # in place — no separate export copy); everything else into the media library
  defp base_directory(source) do
    source = Repo.preload(source, :media_profile)

    if MediaProfile.podcast?(source.media_profile) do
      Application.get_env(:pinchflat, :podcast_directory)
    else
      Application.get_env(:pinchflat, :media_directory)
    end
  end
end
