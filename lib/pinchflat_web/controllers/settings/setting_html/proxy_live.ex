defmodule Pinchflat.Settings.ProxyLive do
  use PinchflatWeb, :live_view

  alias PinchflatWeb.Settings.SettingHTML
  alias Pinchflat.Settings
  alias Pinchflat.Settings.Proxy

  @mode_options [
    {"No proxy", "none"},
    {"Manual proxy URL", "manual"},
    {"Proxy list file (proxy.json)", "file"}
  ]

  def render(assigns) do
    ~H"""
    <form id="proxy-settings-form" phx-change="save">
      <.input
        type="select"
        id="setting_proxy_mode"
        name="proxy_mode"
        value={@mode}
        options={@mode_options}
        label="Proxy Mode"
        help={SettingHTML.proxy_mode_help()}
        html_help={true}
      />

      <.input
        :if={@mode == "manual"}
        type="text"
        id="setting_proxy_url"
        name="proxy_url"
        value={@proxy_url}
        errors={@errors[:proxy_url] || []}
        label="Proxy URL"
        help="Passed to yt-dlp as --proxy. Supports http, https, socks4, and socks5 (eg: http://user:pass@host:8080)"
        inputclass="font-mono text-sm mr-4"
        placeholder="http://user:pass@host:8080"
        phx-debounce="blur"
      >
        <:input_append>
          <span
            :if={@saved}
            class="ml-3 flex shrink-0 items-center gap-1 whitespace-nowrap text-sm font-medium text-meta-3"
            role="status"
          >
            <.icon name="hero-check-circle" class="h-5 w-5" /> Saved
          </span>
          <.icon_button
            icon_name={@icon_name}
            class={"h-12 w-12 disabled:opacity-50 disabled:cursor-not-allowed#{if @testing, do: " animate-spin"}"}
            phx-click="test_proxy"
            tooltip={@tooltip}
            disabled={blank?(@proxy_url) || @testing}
            type="button"
          />
        </:input_append>
      </.input>

      <p :if={@mode == "file"} class="mt-2 max-w-prose text-sm">
        A random proxy is picked from <span class="font-mono">proxy.json</span>
        for each yt-dlp request. Upload and test the file below.
      </p>

      <div class="mt-4">
        <.input
          type="toggle"
          id="setting_proxy_covers_http"
          name="proxy_covers_http"
          value={@covers_http}
          label="Also use proxy for RSS & YouTube API requests"
          help={SettingHTML.proxy_covers_http_help()}
          html_help={true}
        />
      </div>
    </form>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign_from_settings(socket)}
  end

  # Switching *to* manual with no URL yet isn't something we can persist (the URL
  # is required), so just reveal the field and wait for the URL to be entered.
  def handle_event("save", %{"_target" => ["proxy_mode"], "proxy_mode" => "manual"} = params, socket) do
    if blank?(params["proxy_url"]) do
      {:noreply, assign(socket, mode: "manual", proxy_url: params["proxy_url"], saved: false)}
    else
      persist(build_attrs(params), socket)
    end
  end

  def handle_event("save", params, socket) do
    persist(build_attrs(params), socket)
  end

  def handle_event("test_proxy", _params, %{assigns: assigns} = socket) do
    if blank?(assigns.proxy_url) || assigns.testing do
      {:noreply, socket}
    else
      # Run the test off the LiveView process so the UI updates to the spinner
      # immediately and never blocks (an unreachable proxy can take seconds to
      # fail). The result comes back via handle_info/2.
      parent = self()
      url = String.trim(assigns.proxy_url)

      Task.start(fn ->
        result =
          try do
            Proxy.test_connectivity(url)
          rescue
            e -> {:error, Exception.message(e)}
          end

        send(parent, {:test_result, result})
      end)

      {:noreply, assign(socket, %{testing: true, icon_name: "hero-arrow-path", tooltip: "Testing…"})}
    end
  end

  def handle_info({:test_result, result}, socket) do
    # Schedule the neutral-icon reset only now, once we actually have a result —
    # otherwise a slow failure lands after the timer already fired and the icon
    # snaps back to neutral, making it look like nothing happened.
    Process.send_after(self(), :reset_button_icon, 6_000)

    icon_and_tooltip =
      case result do
        {:ok, exit_ip} ->
          %{icon_name: "hero-check", tooltip: "It works! Egress IP: #{exit_ip}"}

        {:error, :unsupported_scheme} ->
          %{
            icon_name: "hero-information-circle",
            tooltip: "Can't auto-test SOCKS/HTTPS proxies (yt-dlp still uses them)"
          }

        {:error, :invalid} ->
          %{icon_name: "hero-x-mark", tooltip: "Invalid proxy URL"}

        {:error, reason} ->
          %{icon_name: "hero-x-mark", tooltip: "Failed: #{reason}"}
      end

    {:noreply, assign(socket, Map.put(icon_and_tooltip, :testing, false))}
  end

  def handle_info(:reset_button_icon, socket) do
    {:noreply, assign(socket, %{icon_name: "hero-signal", tooltip: "Test proxy"})}
  end

  def handle_info(:reset_saved, socket) do
    {:noreply, assign(socket, saved: false)}
  end

  defp persist(attrs, socket) do
    case Settings.update_setting(Settings.record(), attrs) do
      {:ok, _setting} ->
        Process.send_after(self(), :reset_saved, 4_000)
        {:noreply, socket |> assign_from_settings() |> assign(saved: true)}

      {:error, changeset} ->
        # Reflect what they submitted so the offending field (and its error) stays visible.
        assigns = %{
          mode: attrs["proxy_mode"] || socket.assigns.mode,
          proxy_url: Map.get(attrs, "proxy_url", socket.assigns.proxy_url),
          covers_http: (attrs["proxy_covers_http"] || to_string(socket.assigns.covers_http)) == "true",
          errors: field_errors(changeset),
          saved: false
        }

        {:noreply, assign(socket, assigns)}
    end
  end

  # proxy_url is only rendered (and submitted) in manual mode; when absent we
  # leave the stored value untouched rather than clearing it.
  defp build_attrs(params) do
    attrs = %{
      "proxy_mode" => params["proxy_mode"],
      "proxy_covers_http" => params["proxy_covers_http"] || "false"
    }

    if Map.has_key?(params, "proxy_url"), do: Map.put(attrs, "proxy_url", params["proxy_url"]), else: attrs
  end

  defp assign_from_settings(socket) do
    setting = Settings.record()

    assign(socket, %{
      mode: setting.proxy_mode || "none",
      proxy_url: setting.proxy_url,
      covers_http: setting.proxy_covers_http || false,
      mode_options: @mode_options,
      errors: %{},
      saved: false,
      testing: false,
      icon_name: "hero-signal",
      tooltip: "Test proxy"
    })
  end

  defp field_errors(changeset) do
    Enum.reduce(changeset.errors, %{}, fn {field, {msg, _opts}}, acc ->
      Map.update(acc, field, [msg], &[msg | &1])
    end)
  end

  defp blank?(value), do: value in [nil, ""] or String.trim(value) == ""
end
