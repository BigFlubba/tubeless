defmodule Pinchflat.Settings.ProxyFileLive do
  use PinchflatWeb, :live_view

  alias Pinchflat.Settings.ProxyFile
  alias Pinchflat.Settings.Proxy

  def render(assigns) do
    ~H"""
    <div>
      <.label>
        Proxy File
        <span :if={@present} class="ml-2 rounded-full bg-meta-3/20 px-3 py-1 text-xs font-medium text-meta-3">
          Populated
        </span>
        <span :if={!@present} class="ml-2 rounded-full bg-meta-4 px-3 py-1 text-xs font-medium text-bodydark">
          Empty
        </span>
      </.label>

      <.help>{Phoenix.HTML.raw(proxy_help())}</.help>

      <form
        id="proxy-file-form"
        phx-submit="upload_proxy"
        phx-change="validate_upload"
        class="mt-3 flex flex-wrap items-center gap-3"
      >
        <label
          phx-drop-target={@uploads.proxy.ref}
          class={[
            "flex cursor-pointer items-center gap-2 rounded-lg border-[1.5px] border-form-strokedark",
            "bg-form-input px-5 py-3 text-sm text-white hover:bg-meta-4"
          ]}
        >
          <.icon name="hero-arrow-up-tray" class="h-5 w-5" />
          <span>{upload_label(@uploads.proxy.entries)}</span>
          <.live_file_input upload={@uploads.proxy} class="hidden" />
        </label>

        <.button :if={@uploads.proxy.entries != []} type="submit" rounding="rounded-lg" class="px-5! py-3!">
          Save File
        </.button>

        <.link
          :if={@present}
          href={~p"/settings/proxy-file"}
          class={[
            "flex items-center gap-2 rounded-lg border-2 border-strokedark bg-form-input",
            "px-5 py-3 text-sm text-white hover:bg-meta-4"
          ]}
        >
          <.icon name="hero-arrow-down-tray" class="h-5 w-5" /> Download
        </.link>

        <.icon_button
          :if={@present}
          icon_name={@validate_icon}
          class={"h-12 w-12 disabled:opacity-50 disabled:cursor-not-allowed#{if @testing, do: " animate-spin"}"}
          phx-click="test_proxy_file"
          tooltip={@validate_tooltip}
          disabled={@testing}
          type="button"
        />

        <button
          :if={@present}
          type="button"
          phx-click="clear_proxy"
          data-confirm="Clear the proxy file?"
          class={[
            "flex items-center gap-2 rounded-lg border-2 border-strokedark bg-form-input",
            "px-5 py-3 text-sm text-meta-1 hover:bg-meta-4"
          ]}
        >
          <.icon name="hero-trash" class="h-5 w-5" /> Clear
        </button>
      </form>

      <.error :for={err <- upload_errors(@uploads.proxy)}>{error_to_string(err)}</.error>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(%{
        present: ProxyFile.present?(),
        testing: false,
        validate_icon: "hero-signal",
        validate_tooltip: "Validate and test a random proxy"
      })
      |> allow_upload(:proxy, accept: ~w(.json), max_entries: 1, max_file_size: 5_000_000)

    {:ok, socket}
  end

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("upload_proxy", _params, socket) do
    consume_uploaded_entries(socket, :proxy, fn %{path: path}, _entry ->
      {:ok, ProxyFile.save_from_path(path)}
    end)

    {:noreply, assign(socket, present: ProxyFile.present?())}
  end

  def handle_event("clear_proxy", _params, socket) do
    ProxyFile.clear()

    {:noreply, assign(socket, present: false)}
  end

  # Validates the file first (parse + count), then tests one random proxy for
  # real reachability so the button confirms both "the file is good" and "a
  # proxy in it actually works". Runs off the LiveView process so the UI shows a
  # spinner immediately and never blocks (see ProxyLive for the same pattern).
  def handle_event("test_proxy_file", _params, %{assigns: %{testing: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("test_proxy_file", _params, socket) do
    parent = self()

    Task.start(fn ->
      result =
        try do
          compute_file_test_result()
        rescue
          e -> {"hero-x-mark", "Test failed: #{Exception.message(e)}"}
        end

      send(parent, {:file_test_result, result})
    end)

    {:noreply, assign(socket, testing: true, validate_icon: "hero-arrow-path", validate_tooltip: "Testing…")}
  end

  def handle_info({:file_test_result, {icon, tooltip}}, socket) do
    Process.send_after(self(), :reset_validate_icon, 6_000)

    {:noreply, assign(socket, testing: false, validate_icon: icon, validate_tooltip: tooltip)}
  end

  def handle_info(:reset_validate_icon, socket) do
    {:noreply, assign(socket, validate_icon: "hero-signal", validate_tooltip: "Validate and test a random proxy")}
  end

  defp compute_file_test_result do
    case ProxyFile.validate() do
      {:ok, %{count: count}} -> test_random_proxy(count)
      {:error, :empty} -> {"hero-x-mark", "File is empty"}
      {:error, :invalid} -> {"hero-x-mark", "Not a valid proxy.json file"}
    end
  end

  defp test_random_proxy(count) do
    with {:ok, url} <- ProxyFile.random_proxy_url(),
         {:ok, exit_ip} <- Proxy.test_connectivity(url) do
      {"hero-check", "#{count} proxy(ies) — tested one, exit IP #{exit_ip}"}
    else
      {:error, :unsupported_scheme} -> {"hero-information-circle", "#{count} proxy(ies) — can't auto-test SOCKS/HTTPS"}
      {:error, reason} -> {"hero-exclamation-triangle", "#{count} proxy(ies) — test failed: #{reason}"}
    end
  end

  defp upload_label([]), do: "Choose proxy.json"
  defp upload_label([entry | _]), do: entry.client_name

  defp error_to_string(:too_large), do: "File is too large (max 5MB)"
  defp error_to_string(:not_accepted), do: "Only .json files are accepted"
  defp error_to_string(:too_many_files), do: "Only one file can be uploaded"
  defp error_to_string(_), do: "Invalid file"

  defp proxy_help do
    url = "https://github.com/CommunityMaintained/tubeless/wiki/Proxy"

    ~s(Upload a <span class="font-mono">proxy.json</span> list of proxies. When Proxy Mode is set to ) <>
      ~s(<span class="font-mono">Proxy list file</span>, one proxy is picked at random for each yt-dlp request. ) <>
      ~s(See <a href="#{url}" class="#{help_link_classes()}" target="_blank">the wiki</a> for file structure and required keys.)
  end

  defp help_link_classes do
    "underline decoration-bodydark decoration-1 hover:decoration-white"
  end
end
