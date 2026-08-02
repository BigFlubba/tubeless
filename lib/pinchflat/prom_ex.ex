defmodule Pinchflat.PromEx do
  @moduledoc """
  Configuration for the PromEx library which provides Prometheus metrics
  """

  use PromEx, otp_app: :pinchflat

  alias PromEx.Plugins
  alias Pinchflat.PromEx.Plugins.Database

  @impl true
  def plugins do
    [
      Plugins.Application,
      Plugins.Beam,
      Database,
      {Plugins.Phoenix, router: PinchflatWeb.Router, endpoint: PinchflatWeb.Endpoint},
      Plugins.Ecto,
      Plugins.Oban,
      Plugins.PhoenixLiveView
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "oban.json"},
      {:prom_ex, "phoenix_live_view.json"},
      # Custom dashboard for the Database plugin (lives in this app's priv/grafana)
      {:pinchflat, "grafana/database.json"}
    ]
  end
end
