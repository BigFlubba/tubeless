defmodule PinchflatWeb.Settings.SettingHTML do
  use PinchflatWeb, :html

  embed_templates "setting_html/*"

  @doc """
  Renders a setting form.
  """
  attr :conn, Plug.Conn, required: true
  attr :changeset, Ecto.Changeset, required: true
  attr :action, :string, required: true

  def setting_form(assigns)

  def apprise_server_help do
    url = "https://github.com/caronc/apprise/wiki/URLBasics"

    ~s(Server endpoint for Apprise notifications when new media is found. See <a href="#{url}" class="#{help_link_classes()}" target="_blank">Apprise docs</a> for more information)
  end

  def youtube_api_help do
    url = "https://github.com/CommunityMaintained/tubeless/wiki/Generating-a-YouTube-API-key"

    ~s(API key for YouTube Data API v3. Greatly improves the accuracy of Fast Indexing. You can add multiple keys separated by commas &mdash; they'll be used in round-robin fashion to spread quota usage. See <a href="#{url}" class="#{help_link_classes()}" target="_blank">here</a> for details on generating an API key)
  end

  def yt_dlp_update_policy_help do
    ~s(Controls how the bundled yt-dlp is kept up to date. Use "Nightly until stable" to temporarily ride nightly when YouTube breaks something, then auto-return to stable once the fix ships)
  end

  def yt_dlp_pinned_version_help do
    url = "https://github.com/yt-dlp/yt-dlp/releases"

    ~s(The exact yt-dlp version to install and hold, e.g. "2025.12.08". See the <a href="#{url}" class="#{help_link_classes()}" target="_blank">GH releases page</a> for valid versions, or use the check button to validate your entry)
  end

  def proxy_mode_help do
    url = "https://github.com/CommunityMaintained/tubeless/wiki/Proxy"

    ~s(Route <strong>yt-dlp</strong> network traffic through a proxy. <span class="font-mono">Manual proxy URL</span> uses ) <>
      ~s(one fixed proxy; <span class="font-mono">Proxy list file</span> picks a random proxy from ) <>
      ~s(<span class="font-mono">proxy.json</span> file for each request. Applies to all downloads, indexing, and ) <>
      ~s(yt-dlp self-updates. See <a href="#{url}" class="#{help_link_classes()}" target="_blank">the wiki</a> ) <>
      ~s(for setup details)
  end

  def proxy_covers_http_help do
    ~s(By default only <strong>yt-dlp</strong> traffic is proxied. Enable this to also route Tubeless's own RSS feed and ) <>
      ~s(YouTube Data API requests through the proxy. Note: only <strong>http proxies</strong> can cover these requests; ) <>
      ~s(<strong>https and SOCKS proxies</strong> fall back to a direct connection here &mdash; yt-dlp still uses them)
  end

  defp help_link_classes do
    "underline decoration-bodydark decoration-1 hover:decoration-white"
  end
end
