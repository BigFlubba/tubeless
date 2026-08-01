defmodule PinchflatWeb.SettingControllerTest do
  use PinchflatWeb.ConnCase

  alias Pinchflat.Utils.FilesystemUtils

  describe "show settings" do
    test "renders the page", %{conn: conn} do
      conn = get(conn, ~p"/settings")

      assert html_response(conn, 200) =~ "Settings"
    end
  end

  describe "download_cookies" do
    setup do
      base_dir =
        Path.join([
          System.tmp_dir!(),
          "setting_controller_test",
          Integer.to_string(:erlang.unique_integer([:positive]))
        ])

      File.mkdir_p!(base_dir)
      original = Application.get_env(:pinchflat, :extras_directory)
      Application.put_env(:pinchflat, :extras_directory, base_dir)

      on_exit(fn ->
        Application.put_env(:pinchflat, :extras_directory, original)
        File.rm_rf!(base_dir)
      end)

      :ok
    end

    test "sends the cookies file when one exists", %{conn: conn} do
      File.write!(Pinchflat.Settings.CookieFile.filepath(), "some-cookies")

      conn = get(conn, ~p"/settings/cookies")

      assert response(conn, 200) =~ "some-cookies"
    end

    test "redirects with an error when no cookies file exists", %{conn: conn} do
      conn = get(conn, ~p"/settings/cookies")

      assert redirected_to(conn) == ~p"/settings"
      assert conn.assigns[:flash]["error"] == "No cookies file has been uploaded"
    end
  end

  describe "download_logs" do
    test "downloads logs", %{conn: conn} do
      log_path = Path.join([System.tmp_dir!(), "pinchflat", "data", "pinchflat.log"])
      FilesystemUtils.write_p(log_path, "test log data")
      Application.put_env(:pinchflat, :log_path, log_path)

      conn = get(conn, ~p"/download_logs")

      assert response(conn, 200) =~ "test log data"

      Application.put_env(:pinchflat, :log_path, nil)
    end

    test "redirects when log file is not found", %{conn: conn} do
      conn = get(conn, ~p"/download_logs")

      assert redirected_to(conn) == ~p"/diagnostics"
      assert conn.assigns[:flash]["error"] == "Log file couldn't be found"
    end
  end
end
