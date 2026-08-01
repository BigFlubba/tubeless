defmodule Pinchflat.Settings.DefaultCookieBehaviourLive do
  use PinchflatWeb, :live_view

  alias Pinchflat.Settings

  @options [
    {"Disabled", "disabled"},
    {"When Needed", "when_needed"},
    {"All Operations", "all_operations"}
  ]

  def render(assigns) do
    ~H"""
    <form
      id="default-cookie-behaviour-form"
      phx-change="save"
      class="mt-6 border-t border-stroke pt-6 dark:border-strokedark"
    >
      <.input
        type="select"
        id="setting_default_cookie_behaviour"
        name="default_cookie_behaviour"
        value={@behaviour}
        options={@options}
        label="Default Cookie Behavior for New Sources"
        help="The Cookie Behavior pre-selected when adding a new source. Doesn't change existing sources"
      />
    </form>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign_from_settings(socket)}
  end

  # A select persisting its chosen value is its own confirmation, so — like the
  # other selects/toggles on the Settings page — there's no "Saved" indicator.
  def handle_event("save", %{"default_cookie_behaviour" => behaviour}, socket) do
    case Settings.update_setting(Settings.record(), %{default_cookie_behaviour: behaviour}) do
      {:ok, _setting} -> {:noreply, assign_from_settings(socket)}
      {:error, _changeset} -> {:noreply, assign(socket, behaviour: behaviour)}
    end
  end

  defp assign_from_settings(socket) do
    assign(socket, %{
      behaviour: Settings.record().default_cookie_behaviour || "disabled",
      options: @options
    })
  end
end
