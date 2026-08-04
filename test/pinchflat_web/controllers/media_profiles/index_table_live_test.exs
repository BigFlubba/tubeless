defmodule PinchflatWeb.MediaProfiles.MediaProfileLive.IndexTableLiveTest do
  use PinchflatWeb.ConnCase

  import Phoenix.LiveViewTest
  import Pinchflat.MediaFixtures
  import Pinchflat.SourcesFixtures
  import Pinchflat.ProfilesFixtures

  import PinchflatWeb.MediaProfiles.MediaProfileSummary, only: [content_label: 1]

  alias PinchflatWeb.MediaProfiles.MediaProfileLive.IndexTableLive

  describe "initial rendering" do
    test "lists all media profiles", %{conn: conn} do
      media_profile = media_profile_fixture()

      {:ok, _view, html} = live_isolated(conn, IndexTableLive, session: create_session())

      assert html =~ media_profile.name
    end

    test "omits profiles that have marked_for_deletion_at set", %{conn: conn} do
      media_profile = media_profile_fixture(marked_for_deletion_at: DateTime.utc_now())

      {:ok, _view, html} = live_isolated(conn, IndexTableLive, session: create_session())

      refute html =~ media_profile.name
    end

    test "shows the profile's quality and container", %{conn: conn} do
      media_profile_fixture(preferred_resolution: :"2160p", media_container: "mkv")

      {:ok, view, _html} = live_isolated(conn, IndexTableLive, session: create_session())

      assert cell_text(view, "tbody tr:first-child td:nth-of-type(2)") =~ "4K"
      assert cell_text(view, "tbody tr:first-child td:nth-of-type(2)") =~ "mkv"
    end

    test "falls back to the implied mp4 container for video profiles", %{conn: conn} do
      media_profile_fixture(preferred_resolution: :"1080p")

      {:ok, view, _html} = live_isolated(conn, IndexTableLive, session: create_session())

      assert cell_text(view, "tbody tr:first-child td:nth-of-type(2)") =~ "mp4 (default)"
    end

    test "shows All when both content behaviours are the default", %{conn: conn} do
      media_profile_fixture()

      {:ok, view, _html} = live_isolated(conn, IndexTableLive, session: create_session())

      assert cell_text(view, "tbody tr:first-child td:nth-of-type(3)") == "All"
    end

    test "lists the enabled extras as chips", %{conn: conn} do
      media_profile_fixture(download_nfo: true, embed_thumbnail: true, sponsorblock_remove_categories: ["sponsor"])

      {:ok, view, _html} = live_isolated(conn, IndexTableLive, session: create_session())

      extras = cell_text(view, "tbody tr:first-child td:nth-of-type(4)")

      assert extras =~ "Thumbnail"
      assert extras =~ "NFO"
      assert extras =~ "SponsorBlock"
    end

    test "shows None when the profile downloads no extras", %{conn: conn} do
      media_profile_fixture()

      {:ok, view, _html} = live_isolated(conn, IndexTableLive, session: create_session())

      assert cell_text(view, "tbody tr:first-child td:nth-of-type(4)") == "None"
    end

    test "shows source, downloaded, and size totals across the profile's sources", %{conn: conn} do
      media_profile = media_profile_fixture()
      source = source_fixture(media_profile_id: media_profile.id)
      media_item_fixture(%{source_id: source.id, media_size_bytes: 1_000})
      media_item_fixture(%{source_id: source.id, media_filepath: nil})

      {:ok, view, _html} = live_isolated(conn, IndexTableLive, session: create_session())

      assert cell_text(view, "tbody tr:first-child td:nth-of-type(6)") == "1"
      assert cell_text(view, "tbody tr:first-child td:nth-of-type(7)") == "1"
      assert cell_text(view, "tbody tr:first-child td:nth-of-type(8)") == "1000 B"
    end

    test "sums totals over every source using the profile", %{conn: conn} do
      media_profile = media_profile_fixture(name: "AAA_Counted")
      source1 = source_fixture(media_profile_id: media_profile.id)
      source2 = source_fixture(media_profile_id: media_profile.id)
      media_item_fixture(%{source_id: source1.id, media_size_bytes: 1_000})
      media_item_fixture(%{source_id: source2.id, media_size_bytes: 1_000})

      {:ok, view, _html} = live_isolated(conn, IndexTableLive, session: create_session())

      assert cell_text(view, "tbody tr:first-child td:nth-of-type(6)") == "2"
      assert cell_text(view, "tbody tr:first-child td:nth-of-type(7)") == "2"
    end

    test "does not count another profile's sources or media", %{conn: conn} do
      media_profile = media_profile_fixture(name: "AAA_Empty")
      other_profile = media_profile_fixture(name: "ZZZ_Busy")
      other_source = source_fixture(media_profile_id: other_profile.id)
      media_item_fixture(%{source_id: other_source.id, media_size_bytes: 1_000})

      {:ok, view, _html} = live_isolated(conn, IndexTableLive, session: create_session())

      assert render_element(view, "tbody tr:first-child") =~ media_profile.name
      assert cell_text(view, "tbody tr:first-child td:nth-of-type(6)") == "0"
      assert cell_text(view, "tbody tr:first-child td:nth-of-type(7)") == "0"
      assert cell_text(view, "tbody tr:first-child td:nth-of-type(8)") =~ "0"
    end

    test "excludes sources marked for deletion, and their media, from the totals", %{conn: conn} do
      media_profile = media_profile_fixture(name: "AAA_Deleting")

      source =
        source_fixture(media_profile_id: media_profile.id, marked_for_deletion_at: DateTime.utc_now())

      media_item_fixture(%{source_id: source.id, media_size_bytes: 1_000})

      {:ok, view, _html} = live_isolated(conn, IndexTableLive, session: create_session())

      assert render_element(view, "tbody tr:first-child") =~ media_profile.name
      assert cell_text(view, "tbody tr:first-child td:nth-of-type(6)") == "0"
      assert cell_text(view, "tbody tr:first-child td:nth-of-type(7)") == "0"
    end
  end

  describe "when summarizing content behaviours" do
    # The labels have to mirror MediaQuery.format_matching_profile_preference/0's
    # precedence: `:only` wins over the other field's `:exclude`, and both `:only`
    # is a union (shorts OR livestreams), not an intersection
    test "describes every supported shorts/livestream combination", %{conn: conn} do
      expected = %{
        {:include, :include} => "All",
        {:include, :exclude} => "No livestreams",
        {:include, :only} => "Livestreams only",
        {:exclude, :include} => "No Shorts",
        {:exclude, :exclude} => "Regular videos only",
        {:exclude, :only} => "Livestreams only",
        {:only, :include} => "Shorts only",
        {:only, :exclude} => "Shorts only",
        {:only, :only} => "Shorts and livestreams only"
      }

      for {{shorts, livestreams}, label} <- expected do
        profile = media_profile_fixture(shorts_behaviour: shorts, livestream_behaviour: livestreams)

        assert content_label(profile) == label,
               "expected #{inspect({shorts, livestreams})} to render as #{label}"
      end

      # ...and that the label actually reaches the table
      media_profile_fixture(name: "AAA_Union", shorts_behaviour: :only, livestream_behaviour: :only)

      {:ok, view, _html} = live_isolated(conn, IndexTableLive, session: create_session())

      assert cell_text(view, "tbody tr:first-child td:nth-of-type(3)") == "Shorts and livestreams only"
    end
  end

  describe "when deciding whether to show the Subtitles chip" do
    # Mirrors DownloadOptionBuilder.subtitle_options/1 - the chip has to mean
    # "subtitles come out of this profile", not "a subtitle checkbox is ticked"
    test "shows it when subtitles are downloaded", %{conn: conn} do
      media_profile_fixture(download_subs: true)

      assert extras_for(conn) =~ "Subtitles"
    end

    test "shows it when subtitles are embedded into video", %{conn: conn} do
      media_profile_fixture(embed_subs: true, preferred_resolution: :"1080p")

      assert extras_for(conn) =~ "Subtitles"
    end

    test "hides it when only auto-subs are enabled, since that emits nothing on its own", %{conn: conn} do
      media_profile_fixture(download_auto_subs: true)

      assert extras_for(conn) == "None"
    end

    test "hides it for an audio profile that can only embed", %{conn: conn} do
      media_profile_fixture(embed_subs: true, preferred_resolution: :audio)

      assert extras_for(conn) == "None"
    end

    test "shows it for an audio profile whose auto-subs still get written to a file", %{conn: conn} do
      media_profile_fixture(embed_subs: true, download_auto_subs: true, preferred_resolution: :audio)

      assert extras_for(conn) =~ "Subtitles"
    end
  end

  describe "when testing sorting" do
    test "sorts by name by default, without case sensitivity", %{conn: conn} do
      profile1 = media_profile_fixture(name: "Profile_B")
      profile2 = media_profile_fixture(name: "profile_a")

      {:ok, view, _html} = live_isolated(conn, IndexTableLive, session: create_session())

      assert render_element(view, "tbody tr:first-child") =~ profile2.name
      assert render_element(view, "tbody tr:last-child") =~ profile1.name
    end

    test "clicking the header changes the sort direction", %{conn: conn} do
      profile1 = media_profile_fixture(name: "Profile_B")
      profile2 = media_profile_fixture(name: "Profile_A")

      {:ok, view, _html} = live_isolated(conn, IndexTableLive, session: create_session())

      click_element(view, "th", "Name")

      assert render_element(view, "tbody tr:first-child") =~ profile1.name
      assert render_element(view, "tbody tr:last-child") =~ profile2.name
    end

    test "sorts by quality from best to worst, not alphabetically", %{conn: conn} do
      profile1 = media_profile_fixture(name: "Profile_A", preferred_resolution: :audio)
      profile2 = media_profile_fixture(name: "Profile_B", preferred_resolution: :"2160p")

      {:ok, view, _html} = live_isolated(conn, IndexTableLive, session: create_session())

      click_element(view, "th", "Quality")

      assert render_element(view, "tbody tr:first-child") =~ profile2.name
      assert render_element(view, "tbody tr:last-child") =~ profile1.name
    end

    test "sorts by source count", %{conn: conn} do
      profile1 = media_profile_fixture(name: "Has_Sources")
      profile2 = media_profile_fixture(name: "No_Sources")
      source_fixture(media_profile_id: profile1.id)

      {:ok, view, _html} = live_isolated(conn, IndexTableLive, session: create_session())

      click_element(view, "th", "Sources")

      assert render_element(view, "tbody tr:first-child") =~ profile2.name
      assert render_element(view, "tbody tr:last-child") =~ profile1.name
    end

    test "sorts by downloaded count", %{conn: conn} do
      profile1 = media_profile_fixture(name: "Has_Downloads")
      profile2 = media_profile_fixture(name: "No_Downloads")
      source = source_fixture(media_profile_id: profile1.id)
      media_item_fixture(%{source_id: source.id})

      {:ok, view, _html} = live_isolated(conn, IndexTableLive, session: create_session())

      click_element(view, "th", "Downloaded")

      assert render_element(view, "tbody tr:first-child") =~ profile2.name
      assert render_element(view, "tbody tr:last-child") =~ profile1.name
    end

    test "ignores a sort key that isn't a sortable column", %{conn: conn} do
      profile = media_profile_fixture(name: "Profile_A")

      {:ok, view, _html} = live_isolated(conn, IndexTableLive, session: create_session())

      # A hand-crafted payload (not reachable from the rendered headers) must be
      # dropped rather than crashing the LiveView
      render_click(view, "sort_update", %{"sort_key" => "output_path_template"})
      render_click(view, "sort_update", %{"sort_key" => "definitely_not_an_atom_yet"})

      assert render_element(view, "tbody") =~ profile.name
    end

    test "sorts by media size", %{conn: conn} do
      profile = media_profile_fixture(name: "Big_Profile")
      source = source_fixture(media_profile_id: profile.id)
      media_item_fixture(%{source_id: source.id, media_size_bytes: 5_000})

      {:ok, view, _html} = live_isolated(conn, IndexTableLive, session: create_session())

      # media_item_fixture creates stray zero-size profiles, so only the biggest
      # profile has a deterministic position: last when ascending, first when
      # descending
      click_element(view, "th", "Size")
      assert render_element(view, "tbody tr:last-child") =~ profile.name

      click_element(view, "th", "Size")
      assert render_element(view, "tbody tr:first-child") =~ profile.name
    end
  end

  describe "when testing pagination" do
    test "moving to the next page loads new records", %{conn: conn} do
      profile1 = media_profile_fixture(name: "Profile_A")
      profile2 = media_profile_fixture(name: "Profile_B")

      session = Map.merge(create_session(), %{"results_per_page" => 1})
      {:ok, view, _html} = live_isolated(conn, IndexTableLive, session: session)

      assert render_element(view, "tbody") =~ profile1.name
      refute render_element(view, "tbody") =~ profile2.name

      click_element(view, "span.pagination-next")

      refute render_element(view, "tbody") =~ profile1.name
      assert render_element(view, "tbody") =~ profile2.name
    end
  end

  describe "when applying the table density setting" do
    test "uses compact row spacing by default", %{conn: conn} do
      media_profile_fixture()

      {:ok, _view, html} = live_isolated(conn, IndexTableLive, session: create_session())

      assert html =~ "py-2.5"
      refute html =~ "py-5"
    end

    test "uses roomier row spacing when the setting is normal", %{conn: conn} do
      media_profile_fixture()
      Pinchflat.Settings.set(table_density: "normal")

      {:ok, _view, html} = live_isolated(conn, IndexTableLive, session: create_session())

      assert html =~ "py-5"
    end
  end

  defp click_element(view, selector, text_filter \\ nil) do
    view
    |> element(selector, text_filter)
    |> render_click()
  end

  defp render_element(view, selector) do
    view
    |> element(selector)
    |> render()
  end

  defp extras_for(conn) do
    {:ok, view, _html} = live_isolated(conn, IndexTableLive, session: create_session())

    cell_text(view, "tbody tr:first-child td:nth-of-type(4)")
  end

  defp cell_text(view, selector) do
    view
    |> render_element(selector)
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> String.trim()
  end

  defp create_session do
    %{
      "initial_sort_key" => :name,
      "initial_sort_direction" => :asc,
      "results_per_page" => 10
    }
  end
end
