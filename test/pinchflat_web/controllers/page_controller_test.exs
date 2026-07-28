defmodule PinchflatWeb.PageControllerTest do
  use PinchflatWeb.ConnCase

  alias Pinchflat.Settings

  setup do
    stub(DiskSpaceCheckerMock, :space_info, fn _path ->
      {:ok,
       %{
         available_bytes: 10 * 1024 * 1024 * 1024,
         total_bytes: 40 * 1024 * 1024 * 1024,
         used_percent: 75,
         mountpoint: "/"
       }}
    end)

    :ok
  end

  describe "GET / when testing onboarding" do
    test "sets the onboarding setting to true when onboarding", %{conn: conn} do
      _conn = get(conn, ~p"/")
      assert Settings.get!(:onboarding)
    end

    test "displays the onboarding page when onboarding is forced", %{conn: conn} do
      Settings.set(onboarding: false)

      conn = get(conn, ~p"/?onboarding=1")
      assert html_response(conn, 200) =~ "Welcome to Tubeless"
    end

    test "sets the onboarding setting to false if you pass the corrent query param", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert Settings.get!(:onboarding)

      _conn = get(conn, ~p"/?onboarding=0")
      refute Settings.get!(:onboarding)
    end

    test "displays the home page when not onboarding", %{conn: conn} do
      Settings.set(onboarding: false)

      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      assert html =~ "MENU"
      assert html =~ "Sources"
      assert html =~ "Library"
      assert html =~ "Activity"
      assert html =~ "Database"
    end
  end
end
