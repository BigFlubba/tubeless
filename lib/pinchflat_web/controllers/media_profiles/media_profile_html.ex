defmodule PinchflatWeb.MediaProfiles.MediaProfileHTML do
  use PinchflatWeb, :html

  import PinchflatWeb.MediaProfiles.MediaProfileSummary

  alias Pinchflat.Utils.StringUtils
  alias Pinchflat.Profiles.MediaProfile
  alias Pinchflat.Downloading.DownloadOptionBuilder

  embed_templates "media_profile_html/*"

  @doc """
  Renders a media_profile form.
  """
  attr :changeset, Ecto.Changeset, required: true
  attr :action, :string, required: true
  attr :method, :string, required: true

  def media_profile_form(assigns)

  @doc """
  The read-only Details tab: grouped download settings, the effective yt-dlp
  preview, and the internal identifiers box.
  """
  attr :media_profile, :any, required: true
  attr :output_path_override_count, :integer, required: true

  def details_tab(assigns)

  @doc """
  The Sources tab: every source this profile's rules apply to, with what each
  has downloaded so far.
  """
  attr :sources, :list, required: true
  attr :failing_source_ids, :any, required: true

  def sources_tab(assigns)

  def friendly_format_type_options do
    [
      {"Include (default)", :include},
      {"Exclude", :exclude},
      {"Only", :only}
    ]
  end

  # Labels come from MediaProfileSummary so the edit form, the profiles list, and
  # the detail page can't call the same resolution three different things
  def friendly_resolution_options do
    for resolution <- ~w(4320p 2160p 1440p 1080p 720p 480p 360p audio)a do
      {resolution_label(resolution), to_string(resolution)}
    end
  end

  def friendly_sponsorblock_categories do
    [
      {"Sponsor", "sponsor"},
      {"Intro/Intermission", "intro"},
      {"Outro/Credits", "outro"},
      {"Self Promotion", "selfpromo"},
      {"Preview/Recap", "preview"},
      {"Filler Tangent", "filler"},
      {"Interaction Reminder", "interaction"},
      {"Non-music Section", "music_offtopic"},
      {"Hook/Greetings", "hook"}
    ]
  end

  def media_center_custom_output_template_options do
    [
      season_by_year__episode_by_date: "<code>Season YYYY/sYYYYeMMDD</code>",
      season_by_year__episode_by_date_and_index:
        "same as the above but it handles dates better. <strong>This is the recommended option</strong>",
      static_season__episode_by_index:
        "<code>Season 1/s01eXX</code> where <code>XX</code> is the video's position in the playlist. Only recommended for playlists (not channels) that don't change",
      static_season__episode_by_date:
        "<code>Season 1/s01eYYMMDD</code>. Recommended for playlists that might change or where order isn't important",
      series_root:
        "marks the folder it's attached to as the source's root folder for NFOs and artwork (poster, fanart, banner). " <>
          "Use this when your template doesn't use Season folders - for example " <>
          "<code>/{{ source_custom_name }}{{ series_root }}/Videos/{{ title }}.{{ ext }}</code> stores artwork in " <>
          "<code>/{{ source_custom_name }}</code>. It must be attached to a directory name and expands to nothing " <>
          "in the final path. Make sure the marked folder is unique per source (eg: contains " <>
          "<code>{{ source_custom_name }}</code>), otherwise sources will overwrite each other's artwork"
    ]
  end

  def other_custom_output_template_options do
    [
      upload_day: nil,
      upload_month: nil,
      upload_year: nil,
      upload_yyyy_mm_dd: "the upload date in the format <code>YYYY-MM-DD</code>",
      source_custom_name: "the name of the sources that use this profile",
      source_collection_id: "the YouTube ID of the sources that use this profile",
      source_collection_name:
        "the YouTube name of the sources that use this profile (often the same as source_custom_name)",
      source_collection_type: "the collection type of the sources using this profile. Either 'channel' or 'playlist'",
      artist_name: "the name of the artist with fallbacks to other uploader fields",
      season_from_date: "alias for upload_year",
      season_episode_from_date: "the upload date formatted as <code>sYYYYeMMDD</code>",
      season_episode_index_from_date:
        "the upload date formatted as <code>sYYYYeMMDDII</code> where <code>II</code> is an index to prevent date collisions",
      media_playlist_index:
        "the place of the media item in the playlist. Do not use with channels. May not work if the playlist is updated",
      media_item_id: "the ID of the media item in Tubeless's database",
      source_id: "the ID of the source in Tubeless's database",
      media_profile_id: "the ID of the media profile in Tubeless's database"
    ]
  end

  def common_output_template_options do
    ~w(
      id
      ext
      title
      uploader
      channel
      upload_date
      duration_string
    )a
  end

  @doc """
  The Details tab's grouped view of a media profile, replacing the old raw
  attribute dump. Returns a list of `%{title, icon, fields}` groups, where each
  field is a `%{label, value, help, type}` map whose `value` is already a display
  string — the template does no formatting.

  A field whose value is nil or blank is "unset" per `field_set?/1` and stays
  hidden behind the panel's `Show unset fields` toggle rather than being dropped
  here, so the toggle needs no round trip.
  """
  def info_groups(media_profile) do
    [
      %{title: "Quality", icon: "hero-film", fields: quality_fields(media_profile)},
      %{title: "Content", icon: "hero-funnel", fields: content_fields(media_profile)},
      %{title: "Subtitles", icon: "hero-chat-bubble-bottom-center-text", fields: subtitle_fields(media_profile)},
      %{title: "Extra files", icon: "hero-paper-clip", fields: extra_file_fields(media_profile)},
      %{title: "SponsorBlock", icon: "hero-scissors", fields: sponsorblock_fields(media_profile)},
      %{title: "Output", icon: "hero-folder", fields: output_fields(media_profile)}
    ]
  end

  defp quality_fields(media_profile) do
    [
      field(
        "Preferred resolution",
        resolution_label(media_profile.preferred_resolution),
        "The best quality yt-dlp is asked for; it falls back when a video doesn't offer it"
      ),
      field("Container", container_label(media_profile), "The file format media is remuxed into after download"),
      field(
        "Audio track",
        media_profile.audio_track,
        "Preferred audio language or track; unset takes whatever the video defaults to"
      ),
      field(
        "Skip AI-upscaled formats",
        yes_no(media_profile.ignore_youtube_super_resolution),
        "Excludes YouTube Super Resolution formats from every fallback"
      )
    ]
  end

  defp content_fields(media_profile) do
    [
      field("Downloads", content_label(media_profile), "What this profile's sources actually download"),
      # These decide download eligibility (MediaQuery.format_matching_profile_preference/0
      # and Media.SkipReason), NOT what gets indexed - indexing has to read every item
      # to know whether it's a short or a livestream in the first place
      field(
        "Shorts",
        format_behaviour_label(media_profile.shorts_behaviour),
        "Whether Shorts are eligible to download; they're indexed either way"
      ),
      field(
        "Livestreams",
        format_behaviour_label(media_profile.livestream_behaviour),
        "Whether livestreams and their recordings are eligible to download; they're indexed either way"
      )
    ]
  end

  defp subtitle_fields(media_profile) do
    [
      field("Download as files", yes_no(media_profile.download_subs), "Writes a separate .srt file next to the media"),
      field(
        "Include auto-generated",
        yes_no(media_profile.download_auto_subs),
        "Uses YouTube's automatic captions; only applies alongside one of the other two options"
      ),
      field(
        "Embed in media file",
        yes_no(media_profile.embed_subs),
        "Muxes subtitles into the media file; skipped for audio-only profiles"
      ),
      field("Languages", media_profile.sub_langs, "Which subtitle languages are fetched", type: :code)
    ]
  end

  defp extra_file_fields(media_profile) do
    [
      field("Download thumbnail", yes_no(media_profile.download_thumbnail), "Writes a .jpg next to the media"),
      field("Embed thumbnail", yes_no(media_profile.embed_thumbnail), "Muxes the thumbnail into the media file"),
      field(
        "Download source images",
        yes_no(media_profile.download_source_images),
        "Fetches the channel or playlist poster, fanart, and banner"
      ),
      field("Download metadata", yes_no(media_profile.download_metadata), "Writes an .info.json next to the media"),
      field(
        "Embed metadata",
        yes_no(media_profile.embed_metadata),
        "Muxes title, description, and chapters into the file"
      ),
      field("Download NFO", yes_no(media_profile.download_nfo), "Writes an .nfo file for Jellyfin, Kodi, and Plex")
    ]
  end

  defp sponsorblock_fields(media_profile) do
    [
      field(
        "Removed segments",
        sponsorblock_label(media_profile.sponsorblock_remove_categories),
        "These segments are cut out of the downloaded file entirely"
      ),
      field(
        "Marked segments",
        sponsorblock_label(media_profile.sponsorblock_mark_categories),
        "These segments are kept but marked as chapters you can skip"
      )
    ]
  end

  defp output_fields(media_profile) do
    [
      field(
        "Output path template",
        media_profile.output_path_template,
        "Where media downloads to, relative to the media directory",
        type: :long_code
      ),
      field(
        "Publish as podcast",
        yes_no(media_profile.podcast_enabled),
        "Sources download into the podcast library and get a generated feed"
      ),
      field(
        "Redownload delay",
        redownload_delay_label(media_profile.redownload_delay_days),
        "Waits this long after upload, then re-downloads to pick up a better quality version"
      )
    ]
  end

  @doc """
  Presentation attributes for a source row's status pill on the Sources tab.

  Mirrors `Sources.status/2`'s three states, but reads "is this one failing?"
  from the batched `failing_source_ids` set the controller resolved for the whole
  table rather than costing two queries per row.

  Returns %{label: binary(), icon: binary(), class: binary()}
  """
  def source_status_pill(%{enabled: false}, _failing_ids) do
    %{label: "Paused", icon: "hero-pause-circle", class: "bg-warning/15 text-warning"}
  end

  def source_status_pill(source, failing_ids) do
    if MapSet.member?(failing_ids, source.id) do
      %{label: "Error", icon: "hero-exclamation-triangle", class: "bg-danger/15 text-danger"}
    else
      %{label: "Active", icon: "hero-check-circle", class: "bg-success/15 text-success"}
    end
  end

  @doc """
  App-managed identifiers and timestamps, shown as-is under the `Internal` box.
  They're kept because they're the first thing anyone asks for during issue
  triage — they're just no longer the front door.
  """
  def internal_fields(media_profile) do
    [
      {"ID", to_string(media_profile.id)},
      {"Marked for deletion at",
       media_profile.marked_for_deletion_at && to_string(media_profile.marked_for_deletion_at)},
      {"Created at", to_string(media_profile.inserted_at)},
      {"Updated at", to_string(media_profile.updated_at)}
    ]
  end

  @doc """
  Whether an `info_groups/1` field has a value worth showing. Unset fields are
  hidden until the user asks for them.
  """
  def field_set?(%{value: value}), do: is_binary(value) and String.trim(value) != ""

  @doc """
  Pretty-printed JSON for the profile, the same payload as the `Copy JSON` action.
  """
  def media_profile_json(media_profile) do
    media_profile
    |> Phoenix.json_library().encode!()
    |> Jason.Formatter.pretty_print()
  end

  @doc """
  The full path media downloads to under this profile — the base directory a real
  download uses (`DownloadOptionBuilder.base_directory/1`) joined to the template,
  not the bare template, which on its own reads as a path relative to nothing.

  Podcast profiles ignore their output path template entirely (the static server
  and feed URLs depend on the slug-rooted layout), so the preview says so rather
  than showing a template that never runs.

  Returns {binary(), binary() | nil} — the path and an explanation of why it
  isn't the profile's own template, if it isn't.
  """
  def effective_output_path(%{podcast_enabled: true}) do
    {podcast_effective_output_path(),
     "Podcast profiles ignore the output path template — the feed URLs depend on this layout."}
  end

  def effective_output_path(media_profile) do
    {Path.join(media_directory(), media_profile.output_path_template), nil}
  end

  @doc """
  How many of the given sources render somewhere other than the path above,
  because they set their own output path template. The path shown is the
  profile's, and a source override wins over it — so the panel has to say when
  that's actually happening rather than presenting one path as the whole truth.

  **Always 0 for a podcast profile**: `Sources.output_path_template/1` checks
  `podcast?` *before* the override, so a podcast source downloads into the
  slug-rooted podcast library no matter what its override says. Counting those
  would claim sources download elsewhere when they don't, and contradict the
  podcast note shown directly above it.

  Returns integer()
  """
  def output_path_override_count(%{podcast_enabled: true}, _sources), do: 0

  def output_path_override_count(_media_profile, sources) do
    Enum.count(sources, fn source ->
      is_binary(source.output_path_template_override) and String.trim(source.output_path_template_override) != ""
    end)
  end

  @doc """
  The caveat shown under the path above when some of the profile's sources
  render elsewhere, or nil when none do.

  Returns binary() | nil
  """
  def output_path_override_note(0), do: nil

  def output_path_override_note(1) do
    "1 of this profile's sources sets an output path template override and downloads somewhere else."
  end

  def output_path_override_note(count) do
    "#{count} of this profile's sources set an output path template override and download somewhere else."
  end

  defp media_directory, do: Application.get_env(:pinchflat, :media_directory)

  @doc """
  The yt-dlp flags this profile contributes to every download of its media, as
  display-ready strings. Built from `DownloadOptionBuilder.build_profile_options/1`
  so the preview can't drift from what a download actually passes.

  Item-specific flags (output paths, the thumbnail destination, the per-source
  config file) aren't here — they depend on the media item, not the profile.

  Returns [binary()]
  """
  def yt_dlp_option_lines(media_profile) do
    media_profile
    |> DownloadOptionBuilder.build_profile_options()
    |> Enum.map(fn
      {key, value} -> "#{option_flag(key)} #{quote_value(value)}"
      key -> option_flag(key)
    end)
  end

  defp option_flag(key) when is_binary(key), do: key
  defp option_flag(key), do: "--" <> StringUtils.to_kebab_case(to_string(key))

  defp quote_value(value) do
    string = to_string(value)

    if String.contains?(string, " "), do: ~s("#{string}"), else: string
  end

  defp field(label, value, help, opts \\ []) do
    %{
      label: label,
      value: value,
      help: help,
      type: Keyword.get(opts, :type, :text)
    }
  end

  defp yes_no(true), do: "Yes"
  defp yes_no(_), do: "No"

  defp format_behaviour_label(behaviour) do
    case Enum.find(friendly_format_type_options(), fn {_label, value} -> value == behaviour end) do
      {label, _value} -> label
      nil -> behaviour && to_string(behaviour)
    end
  end

  defp sponsorblock_label([]), do: nil

  defp sponsorblock_label(categories) do
    friendly = Map.new(friendly_sponsorblock_categories(), fn {label, value} -> {value, label} end)

    Enum.map_join(categories, ", ", &Map.get(friendly, &1, &1))
  end

  defp redownload_delay_label(nil), do: nil
  defp redownload_delay_label(0), do: "Off"
  defp redownload_delay_label(1), do: "1 day after upload"
  defp redownload_delay_label(days), do: "#{days} days after upload"

  def preset_options do
    [
      {"Default", "default"},
      {"Media Center (Plex, Jellyfin, Kodi, etc.)", "media_center"},
      {"Music", "audio"},
      {"Podcast", "podcast"},
      {"Archiving", "archiving"}
    ]
  end

  # True when podcast feeds can't be generated because the "Podcast URL Base"
  # setting is empty — surfaced next to the podcast toggle so the user learns
  # about the requirement while enabling publishing, not from cancelled jobs
  def podcast_url_base_missing? do
    is_nil(Pinchflat.Settings.get!(:podcast_url_base))
  end

  # True when the podcast library sits inside the media directory (the default:
  # PODCAST_PATH unset, or pointing inside MEDIA_PATH). Media servers scanning
  # the media library will then also index podcast episodes, so a dedicated
  # location is recommended
  def podcast_directory_inside_media_directory? do
    podcast_directory = Path.expand(Application.get_env(:pinchflat, :podcast_directory))
    media_directory = Path.expand(Application.get_env(:pinchflat, :media_directory))

    String.starts_with?(podcast_directory <> "/", media_directory <> "/")
  end

  def podcast_directory, do: Application.get_env(:pinchflat, :podcast_directory)

  # The full path podcast episodes actually download to — shown read-only in
  # place of the output path template while podcast publishing is on, since
  # podcast sources ignore the profile's template entirely
  def podcast_effective_output_path do
    Path.join(podcast_directory(), Pinchflat.Sources.podcast_output_path_template())
  end

  defp default_output_template do
    %MediaProfile{}.output_path_template
  end

  defp media_center_output_template do
    "/shows/{{ source_custom_name }}/{{ season_by_year__episode_by_date_and_index }} - {{ title }}.{{ ext }}"
  end

  defp audio_output_template do
    "/music/{{ artist_name }}/{{ title }}.{{ ext }}"
  end
end
