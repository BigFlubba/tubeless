defmodule PinchflatWeb.Sources.MediaItemTableLiveTest do
  use PinchflatWeb.ConnCase

  import Phoenix.LiveViewTest
  import Pinchflat.MediaFixtures
  import Pinchflat.SourcesFixtures
  import Pinchflat.ProfilesFixtures

  alias PinchflatWeb.Sources.MediaItemTableLive

  setup do
    source = source_fixture()

    {:ok, source: source}
  end

  describe "initial rendering" do
    test "shows message when no records", %{conn: conn, source: source} do
      {:ok, _view, html} = live_isolated(conn, MediaItemTableLive, session: create_session(source))

      assert html =~ "Nothing Here!"
      refute html =~ "Showing"
    end

    test "shows records when present", %{conn: conn, source: source} do
      media_item = media_item_fixture(source_id: source.id, media_filepath: nil)

      {:ok, _view, html} = live_isolated(conn, MediaItemTableLive, session: create_session(source))

      assert html =~ "Showing"
      assert html =~ "Title"
      assert html =~ media_item.title
    end
  end

  describe "media_state" do
    test "shows pending media when pending", %{conn: conn, source: source} do
      downloaded_media_item = media_item_fixture(source_id: source.id)
      pending_media_item = media_item_fixture(source_id: source.id, media_filepath: nil)

      {:ok, _view, html} = live_isolated(conn, MediaItemTableLive, session: create_session(source, "pending"))

      assert html =~ pending_media_item.title
      refute html =~ downloaded_media_item.title
    end

    test "shows downloaded media when downloaded", %{conn: conn, source: source} do
      downloaded_media_item = media_item_fixture(source_id: source.id)
      pending_media_item = media_item_fixture(source_id: source.id, media_filepath: nil)

      {:ok, _view, html} = live_isolated(conn, MediaItemTableLive, session: create_session(source, "downloaded"))

      assert html =~ downloaded_media_item.title
      refute html =~ pending_media_item.title
    end

    test "shows Downloaded and Size columns on the downloaded tab", %{conn: conn, source: source} do
      media_item_fixture(source_id: source.id, media_downloaded_at: DateTime.utc_now(), media_size_bytes: 1_048_576)

      {:ok, _view, html} = live_isolated(conn, MediaItemTableLive, session: create_session(source, "downloaded"))

      assert html =~ "Downloaded"
      assert html =~ "Size"
    end

    test "links each item to its original video on YouTube", %{conn: conn, source: source} do
      media_item = media_item_fixture(source_id: source.id, media_filepath: nil)

      {:ok, _view, html} = live_isolated(conn, MediaItemTableLive, session: create_session(source, "pending"))

      assert html =~ media_item.original_url
      assert html =~ "Watch on YouTube"
    end

    test "shows records that aren't pending or downloaded when other", %{conn: conn} do
      media_profile = media_profile_fixture(shorts_behaviour: :exclude)
      source = source_fixture(media_profile_id: media_profile.id)

      downloaded_media_item = media_item_fixture(source_id: source.id)
      pending_media_item = media_item_fixture(source_id: source.id, media_filepath: nil)
      other_media_item = media_item_fixture(source_id: source.id, media_filepath: nil, short_form_content: true)

      {:ok, _view, html} = live_isolated(conn, MediaItemTableLive, session: create_session(source, "other"))

      assert html =~ other_media_item.title
      refute html =~ downloaded_media_item.title
      refute html =~ pending_media_item.title
    end

    test "shows 'Ignored' status for manually prevented media when other", %{conn: conn, source: source} do
      _media_item = media_item_fixture(source_id: source.id, prevent_download: true, media_filepath: nil)

      {:ok, _view, html} = live_isolated(conn, MediaItemTableLive, session: create_session(source, "other"))

      # Match the chip span, not the reason dropdown's <option> list
      assert html =~ "Status"
      assert html =~ "<span>Ignored</span>"
      refute html =~ "<span>Removed</span>"
    end

    test "shows 'Removed' status for culled media even when prevent_download is set", %{conn: conn, source: source} do
      _media_item =
        media_item_fixture(
          source_id: source.id,
          media_filepath: nil,
          prevent_download: true,
          culled_at: DateTime.utc_now()
        )

      {:ok, _view, html} = live_isolated(conn, MediaItemTableLive, session: create_session(source, "other"))

      assert html =~ "<span>Removed</span>"
      refute html =~ "<span>Ignored</span>"
    end

    test "shows 'Unavailable' status for unavailable media when other", %{conn: conn, source: source} do
      _media_item =
        media_item_fixture(
          source_id: source.id,
          media_filepath: nil,
          prevent_download: true,
          unavailable_at: DateTime.utc_now(),
          unavailable_reason: "members-only content"
        )

      {:ok, _view, html} = live_isolated(conn, MediaItemTableLive, session: create_session(source, "other"))

      assert html =~ "<span>Unavailable</span>"
      refute html =~ "<span>Ignored</span>"
      refute html =~ "<span>Removed</span>"
    end

    test "shows a specific skip reason chip for excluded media when other", %{conn: conn} do
      media_profile = media_profile_fixture(shorts_behaviour: :exclude)
      source = source_fixture(media_profile_id: media_profile.id)
      _media_item = media_item_fixture(source_id: source.id, media_filepath: nil, short_form_content: true)

      {:ok, _view, html} = live_isolated(conn, MediaItemTableLive, session: create_session(source, "other"))

      assert html =~ "<span>Wrong format</span>"
    end
  end

  describe "skip reason filter" do
    setup %{} do
      media_profile = media_profile_fixture()
      source = source_fixture(media_profile_id: media_profile.id, min_duration_seconds: 600, title_filter_regex: "keep")

      too_short =
        media_item_fixture(
          source_id: source.id,
          media_filepath: nil,
          title: "keep this short one",
          duration_seconds: 10
        )

      title_filtered =
        media_item_fixture(source_id: source.id, media_filepath: nil, title: "nope", duration_seconds: 700)

      ignored =
        media_item_fixture(
          source_id: source.id,
          media_filepath: nil,
          prevent_download: true,
          title: "zzz ignored one",
          duration_seconds: 700
        )

      {:ok, source: source, too_short: too_short, title_filtered: title_filtered, ignored: ignored}
    end

    test "only shows the reason dropdown on the Skipped tab", %{conn: conn, source: source} do
      {:ok, _view, other_html} = live_isolated(conn, MediaItemTableLive, session: create_session(source, "other"))
      {:ok, _view, pending_html} = live_isolated(conn, MediaItemTableLive, session: create_session(source, "pending"))

      assert other_html =~ "All reasons"
      refute pending_html =~ "All reasons"
    end

    test "narrows the list to the selected reason", %{
      conn: conn,
      source: source,
      too_short: too_short,
      title_filtered: title_filtered,
      ignored: ignored
    } do
      {:ok, view, html} = live_isolated(conn, MediaItemTableLive, session: create_session(source, "other"))

      # All three excluded items show before filtering
      assert html =~ too_short.title
      assert html =~ title_filtered.title
      assert html =~ ignored.title

      html = render_change(view, "filter_reason", %{"reason" => "too_short"})

      assert html =~ too_short.title
      refute html =~ title_filtered.title
      refute html =~ ignored.title
    end

    test "clearing the reason restores every excluded item", %{
      conn: conn,
      source: source,
      too_short: too_short,
      title_filtered: title_filtered
    } do
      {:ok, view, _html} = live_isolated(conn, MediaItemTableLive, session: create_session(source, "other"))

      render_change(view, "filter_reason", %{"reason" => "too_short"})
      html = render_change(view, "filter_reason", %{"reason" => ""})

      assert html =~ too_short.title
      assert html =~ title_filtered.title
    end
  end

  describe "searching" do
    test "filters records to those matching the search term", %{conn: conn, source: source} do
      matching = media_item_fixture(source_id: source.id, media_filepath: nil, title: "Apple Pie Recipe")
      other = media_item_fixture(source_id: source.id, media_filepath: nil, title: "Banana Bread Recipe")

      {:ok, view, _html} = live_isolated(conn, MediaItemTableLive, session: create_session(source))

      html = render_change(view, "search_term", %{"q" => "apple"})

      assert html =~ matching.title
      refute html =~ other.title
    end

    test "shows the filtered count alongside the total", %{conn: conn, source: source} do
      media_item_fixture(source_id: source.id, media_filepath: nil, title: "Apple Pie Recipe")
      media_item_fixture(source_id: source.id, media_filepath: nil, title: "Banana Bread Recipe")

      {:ok, view, _html} = live_isolated(conn, MediaItemTableLive, session: create_session(source))

      html = render_change(view, "search_term", %{"q" => "apple"})

      # The numbers are wrapped in localization markup, so match loosely
      assert html =~ ~r/Showing.*1.*of.*1/s
    end

    test "an empty search term clears the filter", %{conn: conn, source: source} do
      media_item_fixture(source_id: source.id, media_filepath: nil, title: "Apple Pie Recipe")
      other = media_item_fixture(source_id: source.id, media_filepath: nil, title: "Banana Bread Recipe")

      {:ok, view, _html} = live_isolated(conn, MediaItemTableLive, session: create_session(source))

      render_change(view, "search_term", %{"q" => "apple"})
      html = render_change(view, "search_term", %{"q" => ""})

      assert html =~ other.title
    end
  end

  describe "pagination" do
    test "paginates past the per-page limit", %{conn: conn, source: source} do
      # The table shows 10 records per page, newest upload first
      Enum.each(1..11, fn n ->
        media_item_fixture(
          source_id: source.id,
          media_filepath: nil,
          title: "Video ##{String.pad_leading(to_string(n), 2, "0")}",
          uploaded_at: DateTime.add(DateTime.utc_now(), n, :minute)
        )
      end)

      {:ok, view, html} = live_isolated(conn, MediaItemTableLive, session: create_session(source))

      assert html =~ "Video #11"
      refute html =~ "Video #01"

      html = render_click(view, "page_change", %{"direction" => "inc"})

      assert html =~ "Video #01"
      refute html =~ "Video #11"
    end
  end

  describe "reloading" do
    test "reload_page broadcasts a reload that refetches every table", %{conn: conn, source: source} do
      {:ok, view, html} = live_isolated(conn, MediaItemTableLive, session: create_session(source))
      assert html =~ "Nothing Here!"

      media_item = media_item_fixture(source_id: source.id, media_filepath: nil)

      render_click(view, "reload_page")

      assert render(view) =~ media_item.title
    end
  end

  defp create_session(source, media_state \\ "pending") do
    %{"source_id" => source.id, "media_state" => media_state}
  end
end
