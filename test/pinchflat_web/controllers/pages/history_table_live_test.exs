defmodule PinchflatWeb.Pages.HistoryTableLiveTest do
  use PinchflatWeb.ConnCase

  import Phoenix.LiveViewTest
  import Pinchflat.MediaFixtures
  import Pinchflat.SourcesFixtures

  alias Pinchflat.Pages.HistoryTableLive

  describe "initial rendering" do
    test "shows a message when there are no records", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, HistoryTableLive, session: %{"media_state" => "downloaded"})

      assert html =~ "Nothing Here!"
    end

    test "shows downloaded media when the media_state is downloaded", %{conn: conn} do
      media_item = media_item_fixture(title: "Downloaded Video")

      {:ok, _view, html} = live_isolated(conn, HistoryTableLive, session: %{"media_state" => "downloaded"})

      assert html =~ media_item.title
    end

    test "does not show pending media when the media_state is downloaded", %{conn: conn} do
      media_item = media_item_fixture(title: "Pending Video", media_filepath: nil)

      {:ok, _view, html} = live_isolated(conn, HistoryTableLive, session: %{"media_state" => "downloaded"})

      refute html =~ media_item.title
    end

    test "shows pending media when the media_state is pending", %{conn: conn} do
      media_item = media_item_fixture(title: "Pending Video", media_filepath: nil)

      {:ok, _view, html} = live_isolated(conn, HistoryTableLive, session: %{"media_state" => "pending"})

      assert html =~ media_item.title
    end

    test "links each record to its media item and source", %{conn: conn} do
      media_item = media_item_fixture()

      {:ok, _view, html} = live_isolated(conn, HistoryTableLive, session: %{"media_state" => "downloaded"})

      assert html =~ ~p"/sources/#{media_item.source_id}/media/#{media_item.id}"
      assert html =~ ~p"/sources/#{media_item.source_id}"
    end
  end

  describe "pagination" do
    test "paginates past the per-page limit", %{conn: conn} do
      source = source_fixture()
      # The table shows 5 records per page, newest first
      Enum.each(1..6, fn n -> media_item_fixture(source_id: source.id, title: "Video #{n}") end)

      {:ok, view, html} = live_isolated(conn, HistoryTableLive, session: %{"media_state" => "downloaded"})

      assert html =~ "Video 6"
      refute html =~ "Video 1"

      html = render_click(view, "page_change", %{"direction" => "inc"})

      assert html =~ "Video 1"
      refute html =~ "Video 6"
    end

    test "clamps the page number so it can't go below the first page", %{conn: conn} do
      media_item = media_item_fixture()

      {:ok, view, _html} = live_isolated(conn, HistoryTableLive, session: %{"media_state" => "downloaded"})

      html = render_click(view, "page_change", %{"direction" => "dec"})

      assert html =~ media_item.title
    end
  end

  describe "reloading" do
    test "reload_page refetches the current records", %{conn: conn} do
      {:ok, view, html} = live_isolated(conn, HistoryTableLive, session: %{"media_state" => "downloaded"})
      assert html =~ "Nothing Here!"

      media_item = media_item_fixture()

      html = render_click(view, "reload_page")

      assert html =~ media_item.title
    end

    test "refetches records on job:state change events", %{conn: conn} do
      {:ok, view, html} = live_isolated(conn, HistoryTableLive, session: %{"media_state" => "downloaded"})
      assert html =~ "Nothing Here!"

      media_item = media_item_fixture()
      PinchflatWeb.Endpoint.broadcast("job:state", "change", nil)

      assert render(view) =~ media_item.title
    end
  end
end
