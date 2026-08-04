defmodule PinchflatWeb.MediaProfiles.MediaProfileSummary do
  @moduledoc """
  Plain-language summaries of what a media profile actually downloads.

  Shared by the media profiles index table and the profile detail page so the two
  can never describe the same profile differently.
  """

  @doc """
  Human-readable label for a profile's preferred resolution.

  Returns binary()
  """
  def resolution_label(:"4320p"), do: "8K"
  def resolution_label(:"2160p"), do: "4K"
  def resolution_label(:audio), do: "Audio Only"
  def resolution_label(resolution), do: to_string(resolution)

  @doc """
  Short summary of the container a profile's media ends up in. Video profiles
  with no explicit container get mp4 from yt-dlp, which is worth showing since
  it's what the reconcile format check compares against.

  Returns binary()
  """
  def container_label(%{media_container: container}) when is_binary(container) and container != "", do: container
  def container_label(%{preferred_resolution: :audio}), do: "auto"
  def container_label(_media_profile), do: "mp4 (default)"

  @doc """
  Describes which content types a profile downloads, based on its Shorts and
  livestream behaviours. "All" when both are left at their defaults.

  The clauses mirror the precedence of `MediaQuery.format_matching_profile_preference/0`
  one-for-one so the label can't disagree with what actually downloads: `:only`
  wins over `:exclude` on the other field (the redundant case the schema calls
  out), and both set to `:only` is a *union*, not an intersection.

  Returns binary()
  """
  def content_label(media_profile) do
    case {media_profile.shorts_behaviour, media_profile.livestream_behaviour} do
      {:only, :only} -> "Shorts and livestreams only"
      {:only, _} -> "Shorts only"
      {_, :only} -> "Livestreams only"
      {:exclude, :exclude} -> "Regular videos only"
      {:exclude, _} -> "No Shorts"
      {_, :exclude} -> "No livestreams"
      _ -> "All"
    end
  end

  @doc """
  The list of optional extras a profile downloads or embeds, as short chip
  labels. Empty when the profile grabs the media file and nothing else.

  Returns [binary()]
  """
  def extras_labels(media_profile) do
    [
      {subtitles_enabled?(media_profile), "Subtitles"},
      {media_profile.download_thumbnail || media_profile.embed_thumbnail, "Thumbnail"},
      {media_profile.download_metadata || media_profile.embed_metadata, "Metadata"},
      {media_profile.download_nfo, "NFO"},
      {media_profile.download_source_images, "Images"},
      {sponsorblock_enabled?(media_profile), "SponsorBlock"}
    ]
    |> Enum.filter(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  @doc """
  Whether the profile actually produces subtitles - written to a file or embedded.

  Matches what `DownloadOptionBuilder.subtitle_options/1` does with them rather
  than "any subtitle checkbox is ticked": `download_auto_subs` on its own emits
  nothing (it only qualifies one of the other two), and `embed_subs` is skipped
  for audio profiles - though auto-subs still get written to a file there. That
  last case still emits a bare `sub_langs`, which on its own does nothing.

  Returns boolean()
  """
  def subtitles_enabled?(media_profile) do
    media_profile.download_subs ||
      (media_profile.embed_subs &&
         (media_profile.preferred_resolution != :audio || media_profile.download_auto_subs))
  end

  @doc """
  Whether the profile acts on any SponsorBlock category, in either list.

  Returns boolean()
  """
  def sponsorblock_enabled?(media_profile) do
    media_profile.sponsorblock_mark_categories != [] || media_profile.sponsorblock_remove_categories != []
  end
end
