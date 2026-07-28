defmodule PinchflatWeb.Settings.ProxyFileLiveTest do
  use PinchflatWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Pinchflat.Settings.ProxyFileLive
  alias Pinchflat.Settings.ProxyFile

  setup do
    base_dir =
      Path.join([System.tmp_dir!(), "proxy_live_test", Integer.to_string(:erlang.unique_integer([:positive]))])

    File.mkdir_p!(base_dir)
    original = Application.get_env(:pinchflat, :extras_directory)
    Application.put_env(:pinchflat, :extras_directory, base_dir)

    on_exit(fn ->
      Application.put_env(:pinchflat, :extras_directory, original)
      File.rm_rf!(base_dir)
    end)

    :ok
  end

  @sample Jason.encode!([%{"host" => "203.0.113.10", "port" => 8080, "protocol" => "http"}])

  describe "initial rendering" do
    test "shows the Empty badge when no proxy file is present", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, ProxyFileLive)

      assert html =~ "Empty"
      refute html =~ "Populated"
    end

    test "shows the Populated badge, download and clear when a proxy file exists", %{conn: conn} do
      File.write!(ProxyFile.filepath(), @sample)
      {:ok, _view, html} = live_isolated(conn, ProxyFileLive)

      assert html =~ "Populated"
      assert html =~ "Download"
      assert html =~ "Clear"
    end
  end

  describe "clearing the proxy file" do
    test "blanks the file and updates the UI", %{conn: conn} do
      File.write!(ProxyFile.filepath(), @sample)
      {:ok, view, _html} = live_isolated(conn, ProxyFileLive)

      html = view |> element("button", "Clear") |> render_click()

      assert html =~ "Empty"
      refute ProxyFile.present?()
    end
  end

  describe "testing the proxy file" do
    test "shows an in-progress spinner immediately on click", %{conn: conn} do
      File.write!(ProxyFile.filepath(), @sample)
      {:ok, view, _html} = live_isolated(conn, ProxyFileLive)

      # The actual test runs asynchronously; the click render shows the spinner.
      html = view |> element("[phx-click=test_proxy_file]") |> render_click()

      assert html =~ "animate-spin"
      assert html =~ "Testing"
    end

    test "renders the async result once it arrives", %{conn: conn} do
      File.write!(ProxyFile.filepath(), @sample)
      {:ok, view, _html} = live_isolated(conn, ProxyFileLive)

      send(view.pid, {:file_test_result, {"hero-x-mark", "Not a valid proxy.json file"}})
      html = render(view)

      assert html =~ "hero-x-mark"
      assert html =~ "Not a valid"
    end
  end
end
