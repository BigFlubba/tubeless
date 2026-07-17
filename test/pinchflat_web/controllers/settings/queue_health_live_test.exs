defmodule PinchflatWeb.Settings.QueueHealthLiveTest do
  use PinchflatWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Pinchflat.Settings.QueueHealthLive

  describe "initial rendering" do
    test "renders the queue health section", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, QueueHealthLive)

      assert html =~ "Queue Health"
      assert html =~ "Refresh"
    end

    test "renders a card per configured queue", %{conn: conn} do
      original = Application.get_env(:pinchflat, Oban, [])
      on_exit(fn -> Application.put_env(:pinchflat, Oban, original) end)
      Application.put_env(:pinchflat, Oban, Keyword.put(original, :queues, media_fetching: 2))

      {:ok, _view, html} = live_isolated(conn, QueueHealthLive)

      assert html =~ "Media Fetching"
    end
  end

  describe "refresh" do
    test "re-renders the section in place", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, QueueHealthLive)

      assert render_click(view, "refresh") =~ "Queue Health"
    end
  end
end
