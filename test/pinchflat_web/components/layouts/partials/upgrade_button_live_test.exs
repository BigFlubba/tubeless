defmodule PinchflatWeb.Layouts.Partials.UpgradeButtonLiveTest do
  use PinchflatWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Pinchflat.Settings
  alias Pinchflat.UpgradeButtonLive

  describe "unlocking pro" do
    test "the button starts disabled", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, UpgradeButtonLive, session: %{})

      assert has_element?(view, "button[disabled]")
    end

    test "typing the magic words enables the button and sets pro_enabled", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, UpgradeButtonLive, session: %{})

      render_change(view, "check_matching_text", %{"unlock-pro-textbox" => "got it"})

      refute has_element?(view, "button[disabled]")
      assert {:ok, true} = Settings.get(:pro_enabled)
    end

    test "ignores case and surrounding whitespace", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, UpgradeButtonLive, session: %{})

      render_change(view, "check_matching_text", %{"unlock-pro-textbox" => "  GoT It  "})

      refute has_element?(view, "button[disabled]")
    end

    test "keeps the button disabled for any other text", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, UpgradeButtonLive, session: %{})

      render_change(view, "check_matching_text", %{"unlock-pro-textbox" => "please"})

      assert has_element?(view, "button[disabled]")
      assert {:ok, false} = Settings.get(:pro_enabled)
    end
  end
end
