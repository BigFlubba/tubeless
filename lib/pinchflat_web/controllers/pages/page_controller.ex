defmodule PinchflatWeb.Pages.PageController do
  use PinchflatWeb, :controller

  alias Pinchflat.Diagnostics.SystemStatus
  alias Pinchflat.Profiles.MediaProfile
  alias Pinchflat.Repo
  alias Pinchflat.Sources.Source

  def home(conn, params) do
    done_onboarding = params["onboarding"] == "0"
    force_onboarding = params["onboarding"] == "1"

    if done_onboarding, do: Settings.set(onboarding: false)

    if force_onboarding || Settings.get!(:onboarding) do
      render_onboarding_page(conn)
    else
      render_home_page(conn)
    end
  end

  defp render_home_page(conn) do
    conn
    |> render(:home, system_status: SystemStatus.get())
  end

  defp render_onboarding_page(conn) do
    Settings.set(onboarding: true)

    conn
    |> render(:onboarding_checklist,
      media_profiles_exist: Repo.exists?(MediaProfile),
      sources_exist: Repo.exists?(Source),
      layout: {Layouts, :onboarding}
    )
  end
end
