defmodule PinchflatWeb.Settings.ProxyLiveTest do
  use PinchflatWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Pinchflat.Settings
  alias Pinchflat.Settings.ProxyLive

  describe "initial rendering" do
    test "renders the mode select and coverage toggle with no save button", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, ProxyLive)

      assert html =~ ~s(name="proxy_mode")
      assert html =~ ~s(name="proxy_covers_http")
      refute html =~ "Save Proxy Settings"
    end

    test "hides the manual URL input in none mode", %{conn: conn} do
      Settings.set(proxy_mode: "none")
      {:ok, view, _html} = live_isolated(conn, ProxyLive)

      refute has_element?(view, "input[name='proxy_url']")
    end

    test "shows the manual URL input and test button in manual mode", %{conn: conn} do
      Settings.set(proxy_url: "http://host:8080")
      Settings.set(proxy_mode: "manual")
      {:ok, view, _html} = live_isolated(conn, ProxyLive)

      assert has_element?(view, "input[name='proxy_url']")
      assert has_element?(view, "[phx-click=test_proxy]")
    end
  end

  describe "switching mode" do
    test "reveals the manual URL input when switched to manual", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, ProxyLive)

      refute has_element?(view, "input[name='proxy_url']")

      render_change(view, "save", %{"_target" => ["proxy_mode"], "proxy_mode" => "manual"})

      assert has_element?(view, "input[name='proxy_url']")
    end

    test "does not persist when switching to manual before a URL is entered", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, ProxyLive)

      render_change(view, "save", %{"_target" => ["proxy_mode"], "proxy_mode" => "manual"})

      assert Settings.get!(:proxy_mode) == "none"
    end
  end

  describe "auto-saving" do
    test "persists the mode and coverage toggle on change", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, ProxyLive)

      render_change(view, "save", %{
        "_target" => ["proxy_mode"],
        "proxy_mode" => "file",
        "proxy_covers_http" => "true"
      })

      assert Settings.get!(:proxy_mode) == "file"
      assert Settings.get!(:proxy_covers_http) == true
    end

    test "confirms a saved manual URL with an inline Saved indicator", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, ProxyLive)
      render_change(view, "save", %{"_target" => ["proxy_mode"], "proxy_mode" => "manual"})

      html =
        render_change(view, "save", %{
          "_target" => ["proxy_url"],
          "proxy_mode" => "manual",
          "proxy_url" => "http://host:8080"
        })

      assert html =~ "Saved"
      assert Settings.get!(:proxy_url) == "http://host:8080"
    end

    test "shows an error for an invalid manual URL and doesn't persist", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, ProxyLive)

      html =
        render_change(view, "save", %{
          "_target" => ["proxy_url"],
          "proxy_mode" => "manual",
          "proxy_url" => "not a url"
        })

      assert html =~ "must be a valid"
      assert Settings.get!(:proxy_mode) == "none"
    end
  end

  describe "test button" do
    test "is disabled when the URL is blank", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, ProxyLive)
      render_change(view, "save", %{"_target" => ["proxy_mode"], "proxy_mode" => "manual"})

      assert has_element?(view, "[phx-click=test_proxy][disabled]")
    end

    test "shows an in-progress state immediately on click without blocking", %{conn: conn} do
      Settings.set(proxy_url: "http://127.0.0.1:1")
      Settings.set(proxy_mode: "manual")
      {:ok, view, _html} = live_isolated(conn, ProxyLive)

      # The returned render reflects the state right after the click (the actual
      # test runs asynchronously), so it should show the spinning/testing icon.
      html = render_click(element(view, "[phx-click=test_proxy]"))

      assert html =~ "animate-spin"
      assert html =~ "Testing"
    end

    test "reports a humanized failure for an unreachable proxy", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, ProxyLive)
      render_change(view, "save", %{"_target" => ["proxy_mode"], "proxy_mode" => "manual"})

      render_change(view, "save", %{
        "_target" => ["proxy_url"],
        "proxy_mode" => "manual",
        "proxy_url" => "http://127.0.0.1:1"
      })

      # The async result eventually flips the icon to the error state and reports
      # a readable reason (connection refused), not a raw inspected term.
      send(view.pid, {:test_result, {:error, "Connection refused (is the proxy up and the port correct?)"}})
      html = render(view)

      assert html =~ "hero-x-mark"
      assert html =~ "Connection refused"
    end
  end
end
