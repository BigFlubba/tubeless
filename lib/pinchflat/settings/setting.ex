defmodule Pinchflat.Settings.Setting do
  @moduledoc """
  The Setting schema.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Pinchflat.YtDlp.UpdateManager

  @allowed_fields [
    :onboarding,
    :yt_dlp_version,
    :yt_dlp_update_policy,
    :yt_dlp_pinned_version,
    :yt_dlp_nightly_baseline,
    :apprise_version,
    :apprise_server,
    :video_codec_preference,
    :audio_codec_preference,
    :youtube_api_key,
    :extractor_sleep_interval_seconds,
    :download_throughput_limit,
    :restrict_filenames,
    :ignore_unavailable_media,
    :database_maintenance_enabled,
    :podcast_url_base,
    :proxy_mode,
    :proxy_url,
    :proxy_covers_http,
    :time_format,
    :default_cookie_behaviour
  ]

  @proxy_modes ~w(none manual file)
  @time_formats ~w(24h 12h)
  @cookie_behaviours ~w(disabled when_needed all_operations)

  @required_fields [
    :onboarding,
    :video_codec_preference,
    :audio_codec_preference,
    :extractor_sleep_interval_seconds
  ]

  schema "settings" do
    field :onboarding, :boolean, default: true
    field :yt_dlp_version, :string
    field :yt_dlp_update_policy, :string, default: "stable"
    field :yt_dlp_pinned_version, :string
    field :yt_dlp_nightly_baseline, :string
    field :apprise_version, :string
    field :apprise_server, :string
    field :youtube_api_key, :string
    field :route_token, :string
    field :extractor_sleep_interval_seconds, :integer, default: 0
    # This is a string because it accepts values like "100K" or "4.2M"
    field :download_throughput_limit, :string
    field :restrict_filenames, :boolean, default: false
    field :ignore_unavailable_media, :boolean, default: false
    field :database_maintenance_enabled, :boolean, default: false
    # The public origin of the static file server hosting podcast exports
    # (eg: "http://pods.local"). Tubeless can't know this, so the user sets it
    field :podcast_url_base, :string

    # Proxy configuration for yt-dlp (and optionally RSS/API) network traffic.
    # proxy_mode: "none" | "manual" | "file". "manual" uses proxy_url verbatim;
    # "file" picks a random proxy from proxy.json per yt-dlp invocation
    field :proxy_mode, :string, default: "none"
    field :proxy_url, :string
    field :proxy_covers_http, :boolean, default: false

    # Clock used when rendering timestamps in the UI: "24h" | "12h"
    field :time_format, :string, default: "24h"

    # The cookie behaviour pre-selected when adding a new source:
    # "disabled" | "when_needed" | "all_operations"
    field :default_cookie_behaviour, :string, default: "disabled"

    field :video_codec_preference, :string
    field :audio_codec_preference, :string
  end

  @doc false
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, @allowed_fields)
    |> validate_required(@required_fields)
    |> validate_number(:extractor_sleep_interval_seconds, greater_than_or_equal_to: 0)
    |> validate_inclusion(:yt_dlp_update_policy, UpdateManager.policies())
    |> validate_podcast_url_base()
    |> validate_pinned_version()
    |> validate_inclusion(:proxy_mode, @proxy_modes)
    |> validate_inclusion(:time_format, @time_formats)
    |> validate_inclusion(:default_cookie_behaviour, @cookie_behaviours)
    |> validate_proxy_url()
  end

  @doc """
  The allowed cookie behaviours (matching Source.cookie_behaviour).
  """
  def cookie_behaviours, do: @cookie_behaviours

  @doc """
  The allowed proxy modes.
  """
  def proxy_modes, do: @proxy_modes

  @doc """
  The allowed time formats.
  """
  def time_formats, do: @time_formats

  # In "manual" mode a proxy URL is required and must be a well-formed proxy URL.
  # yt-dlp accepts http, https, socks4, and socks5 schemes. In other modes the
  # field is ignored, so it isn't validated.
  defp validate_proxy_url(changeset) do
    if get_field(changeset, :proxy_mode) == "manual" do
      changeset
      |> validate_required([:proxy_url])
      |> validate_change(:proxy_url, fn :proxy_url, value ->
        case URI.new(value) do
          {:ok, %URI{scheme: scheme, host: host}}
          when scheme in ["http", "https", "socks4", "socks5", "socks5h"] and is_binary(host) and host != "" ->
            []

          _ ->
            [proxy_url: "must be a valid http(s)/socks proxy URL (eg: http://user:pass@host:8080)"]
        end
      end)
    else
      changeset
    end
  end

  # The URL base is user-supplied free text that gets concatenated with paths
  # to build feed/enclosure URLs, so it must be a clean absolute http(s) origin.
  # `URI.new/1` (unlike `URI.parse/1`) rejects illegal characters such as the
  # quotes that would otherwise break/inject XML attributes, and we additionally
  # reject query strings and fragments since appending a path to them is invalid.
  defp validate_podcast_url_base(changeset) do
    validate_change(changeset, :podcast_url_base, fn :podcast_url_base, value ->
      case URI.new(value) do
        {:ok, %URI{scheme: scheme, host: host, query: nil, fragment: nil}}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []

        _ ->
          [podcast_url_base: "must be an absolute http(s) URL with no query string or fragment"]
      end
    end)
  end

  defp validate_pinned_version(changeset) do
    if get_field(changeset, :yt_dlp_update_policy) == "pinned" do
      validate_required(changeset, [:yt_dlp_pinned_version])
    else
      changeset
    end
  end
end
