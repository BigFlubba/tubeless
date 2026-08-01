defmodule PinchflatWeb.Settings.SettingController do
  use PinchflatWeb, :controller

  alias Pinchflat.Settings.CookieFile
  alias Pinchflat.Settings.ProxyFile

  # The settings form is a self-saving LiveView (`MainSettingsLive`), so there is
  # no `update` action — this controller only renders the shell and handles the
  # file downloads that can't be done from a LiveView.
  def show(conn, _params) do
    render(conn, "show.html")
  end

  def download_cookies(conn, _params) do
    if CookieFile.present?() do
      send_download(conn, {:file, CookieFile.filepath()}, filename: "cookies.txt")
    else
      conn
      |> put_flash(:error, "No cookies file has been uploaded")
      |> redirect(to: ~p"/settings")
    end
  end

  def download_proxy_file(conn, _params) do
    if ProxyFile.present?() do
      send_download(conn, {:file, ProxyFile.filepath()}, filename: "proxy.json")
    else
      conn
      |> put_flash(:error, "No proxy file has been uploaded")
      |> redirect(to: ~p"/settings")
    end
  end

  def download_logs(conn, _params) do
    log_path = Application.get_env(:pinchflat, :log_path)

    if log_path && File.exists?(log_path) do
      send_download(conn, {:file, log_path}, filename: "tubeless-logs-#{Date.utc_today()}.txt")
    else
      conn
      |> put_flash(:error, "Log file couldn't be found")
      |> redirect(to: ~p"/diagnostics")
    end
  end
end
