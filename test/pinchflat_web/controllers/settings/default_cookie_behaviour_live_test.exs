defmodule PinchflatWeb.Settings.DefaultCookieBehaviourLiveTest do
  use PinchflatWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Pinchflat.Settings
  alias Pinchflat.Settings.DefaultCookieBehaviourLive

  describe "initial rendering" do
    test "renders the select seeded from settings, with no save button", %{conn: conn} do
      Settings.set(default_cookie_behaviour: "when_needed")

      {:ok, _view, html} = live_isolated(conn, DefaultCookieBehaviourLive)

      assert html =~ ~s(name="default_cookie_behaviour")
      refute html =~ ">Save<"
    end
  end

  describe "auto-saving" do
    test "persists the selection on change", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, DefaultCookieBehaviourLive)

      render_change(view, "save", %{"default_cookie_behaviour" => "all_operations"})

      assert Settings.get!(:default_cookie_behaviour) == "all_operations"
    end
  end
end
