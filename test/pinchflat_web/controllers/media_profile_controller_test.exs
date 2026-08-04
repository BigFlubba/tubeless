defmodule PinchflatWeb.MediaProfileControllerTest do
  use PinchflatWeb.ConnCase

  import Pinchflat.MediaFixtures
  import Pinchflat.SourcesFixtures
  import Pinchflat.ProfilesFixtures

  alias Pinchflat.Repo
  alias Pinchflat.Settings
  alias Pinchflat.Profiles.MediaProfileDeletionWorker
  alias Pinchflat.SlowIndexing.MediaCollectionIndexingWorker

  @create_attrs %{name: "some name", output_path_template: "output_template.{{ ext }}"}
  @update_attrs %{
    name: "some updated name",
    output_path_template: "new_output_template.{{ ext }}"
  }
  @invalid_attrs %{name: nil, output_path_template: nil}

  setup do
    Settings.set(onboarding: false)

    :ok
  end

  describe "index" do
    test "lists all media_profiles", %{conn: conn} do
      profile = media_profile_fixture()
      conn = get(conn, ~p"/media_profiles")

      assert html_response(conn, 200) =~ "Media Profiles"
      assert html_response(conn, 200) =~ profile.name
    end

    test "omits profiles that have marked_for_deletion_at set", %{conn: conn} do
      profile = media_profile_fixture(marked_for_deletion_at: DateTime.utc_now())
      conn = get(conn, ~p"/media_profiles")
      refute html_response(conn, 200) =~ profile.name
    end
  end

  describe "show media_profile" do
    setup do
      {:ok, media_profile: media_profile_fixture()}
    end

    # The header strip is a <dl>; grab the <dd> belonging to a given <dt> label
    defp metric_text(html, label) do
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("dl div")
      |> Enum.find(fn cell -> cell |> LazyHTML.query("dt") |> LazyHTML.text() |> String.trim() == label end)
      |> LazyHTML.query("dd")
      |> LazyHTML.text()
      |> String.trim()
    end

    test "renders the profile's name and download summary in the header", %{conn: conn, media_profile: profile} do
      conn = get(conn, ~p"/media_profiles/#{profile}")
      html = html_response(conn, 200)

      assert html =~ profile.name
      assert html =~ "Sources"
      assert html =~ "Downloaded"
      assert html =~ "Quality"
    end

    test "renders grouped download settings instead of a raw attribute dump", %{conn: conn, media_profile: profile} do
      conn = get(conn, ~p"/media_profiles/#{profile}")
      html = html_response(conn, 200)

      assert html =~ "Download settings"
      assert html =~ "Preferred resolution"
      assert html =~ "Show unset fields"
      refute html =~ "Raw Attributes"
    end

    test "renders the effective yt-dlp preview", %{conn: conn, media_profile: profile} do
      conn = get(conn, ~p"/media_profiles/#{profile}")
      html = html_response(conn, 200)

      assert html =~ "Effective yt-dlp options"
      assert html =~ "Media downloads to"
      assert html =~ "--remux-video mp4"
    end

    test "renders the internal box with a raw JSON view", %{conn: conn, media_profile: profile} do
      conn = get(conn, ~p"/media_profiles/#{profile}")
      html = html_response(conn, 200)

      assert html =~ "Internal"
      assert html =~ "Raw JSON"
    end

    test "lists the sources using the profile with what they've downloaded", %{conn: conn, media_profile: profile} do
      source = source_fixture(%{media_profile_id: profile.id, custom_name: "Cool Channel"})
      media_item_fixture(%{source_id: source.id, media_filepath: "/video.mp4", media_size_bytes: 1_000})

      conn = get(conn, ~p"/media_profiles/#{profile}")
      html = html_response(conn, 200)

      assert html =~ "Cool Channel"
      assert html =~ "Active"
    end

    test "flags a source whose latest job is failing", %{conn: conn, media_profile: profile} do
      source = source_fixture(%{media_profile_id: profile.id})
      {:ok, job} = %{"id" => source.id} |> MediaCollectionIndexingWorker.new() |> Oban.insert()

      job = job |> Ecto.Changeset.change(state: "discarded") |> Repo.update!()
      Pinchflat.Tasks.create_task(job, source)

      conn = get(conn, ~p"/media_profiles/#{profile}")

      assert html_response(conn, 200) =~ "Error"
    end

    # `download_media` is a setting, not a live state, and it's independent of
    # `enabled` - a bare check mark on a paused source reads as "downloading now"
    test "says a paused source isn't downloading even with download_media on", %{conn: conn, media_profile: profile} do
      source_fixture(%{media_profile_id: profile.id, enabled: false, download_media: true})

      conn = get(conn, ~p"/media_profiles/#{profile}")
      html = html_response(conn, 200)

      assert html =~ "Downloads media"
      assert html =~ "nothing downloads until it&#39;s resumed"
    end

    test "totals only count media belonging to this profile's sources", %{conn: conn, media_profile: profile} do
      source = source_fixture(%{media_profile_id: profile.id})
      media_item_fixture(%{source_id: source.id, media_filepath: "/a.mp4", media_size_bytes: 1_500})
      media_item_fixture(%{source_id: source.id, media_filepath: "/b.mp4", media_size_bytes: 500})
      # not downloaded - counts toward neither total
      media_item_fixture(%{source_id: source.id, media_filepath: nil, media_size_bytes: 999})

      other_source = source_fixture(%{media_profile_id: media_profile_fixture().id})
      media_item_fixture(%{source_id: other_source.id, media_filepath: "/c.mp4", media_size_bytes: 9_000_000})

      html = conn |> get(~p"/media_profiles/#{profile}") |> html_response(200)

      downloaded = metric_text(html, "Downloaded")

      assert downloaded =~ ~r/\A2\b/
      assert downloaded =~ "2 KiB"
      # the other profile's much larger source is not folded into this profile's size
      refute downloaded =~ "MiB"
    end

    test "omits sources marked for deletion, like the profiles index does", %{conn: conn, media_profile: profile} do
      source_fixture(%{media_profile_id: profile.id, custom_name: "Live Channel"})

      deleted = source_fixture(%{media_profile_id: profile.id, custom_name: "Deleted Channel"})
      {:ok, _} = Pinchflat.Sources.update_source(deleted, %{marked_for_deletion_at: DateTime.utc_now()})
      media_item_fixture(%{source_id: deleted.id, media_filepath: "/gone.mp4", media_size_bytes: 4_000})

      html = conn |> get(~p"/media_profiles/#{profile}") |> html_response(200)

      assert html =~ "Live Channel"
      refute html =~ "Deleted Channel"
      # its media doesn't quietly inflate the header totals either
      assert metric_text(html, "Sources") == "1"
      assert metric_text(html, "Downloaded") =~ ~r/\A0\b/
    end

    test "notes when a source overrides the profile's output path", %{conn: conn, media_profile: profile} do
      source_fixture(%{media_profile_id: profile.id, output_path_template_override: "/elsewhere/{{ title }}.{{ ext }}"})

      html = conn |> get(~p"/media_profiles/#{profile}") |> html_response(200)

      assert html =~ "output path template override"
    end

    test "makes no override claim on a podcast profile, which ignores overrides", %{conn: conn} do
      profile = media_profile_fixture(%{podcast_enabled: true})
      source_fixture(%{media_profile_id: profile.id, output_path_template_override: "/elsewhere/{{ title }}.{{ ext }}"})

      html = conn |> get(~p"/media_profiles/#{profile}") |> html_response(200)

      # the podcast layout wins over the override, so the source does NOT download elsewhere
      refute html =~ "output path template override"
      assert html =~ "Podcast profiles ignore the output path template"
    end

    test "explains itself when nothing uses the profile", %{conn: conn, media_profile: profile} do
      conn = get(conn, ~p"/media_profiles/#{profile}")

      assert html_response(conn, 200) =~ "No sources use this media profile yet"
    end
  end

  describe "new media_profile" do
    test "renders form", %{conn: conn} do
      conn = get(conn, ~p"/media_profiles/new")
      html = html_response(conn, 200)

      assert html =~ "New Media Profile"
      assert html =~ "Ignore YouTube Super Resolution"
      assert html =~ ~s(name="media_profile[ignore_youtube_super_resolution]")
    end

    test "renders correct layout when onboarding", %{conn: conn} do
      Settings.set(onboarding: true)
      conn = get(conn, ~p"/media_profiles/new")

      refute html_response(conn, 200) =~ "<span>MENU</span>"
    end
  end

  describe "create media_profile" do
    test "redirects to show when data is valid", %{conn: conn} do
      conn = post(conn, ~p"/media_profiles", media_profile: @create_attrs)

      assert %{id: id} = redirected_params(conn)
      assert redirected_to(conn) == ~p"/media_profiles/#{id}"

      conn = get(conn, ~p"/media_profiles/#{id}")
      assert html_response(conn, 200) =~ "Media Profile"
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, ~p"/media_profiles", media_profile: @invalid_attrs)
      assert html_response(conn, 200) =~ "New Media Profile"
    end

    test "redirects to onboarding when onboarding", %{conn: conn} do
      Settings.set(onboarding: true)
      conn = post(conn, ~p"/media_profiles", media_profile: @create_attrs)

      assert redirected_to(conn) == ~p"/?onboarding=1"
    end

    test "renders correct layout on error when onboarding", %{conn: conn} do
      Settings.set(onboarding: true)
      conn = post(conn, ~p"/media_profiles", media_profile: @invalid_attrs)

      refute html_response(conn, 200) =~ "MENU"
    end

    test "preloads some attributes when using a template", %{conn: conn} do
      profile = media_profile_fixture(name: "My first profile", download_subs: true, sub_langs: "de")

      conn = get(conn, ~p"/media_profiles/new", %{"template_id" => profile.id})
      assert html_response(conn, 200) =~ "New Media Profile"
      assert html_response(conn, 200) =~ profile.sub_langs
      refute html_response(conn, 200) =~ profile.name
    end
  end

  describe "edit media_profile" do
    setup [:create_media_profile]

    test "renders form for editing chosen media_profile", %{
      conn: conn,
      media_profile: media_profile
    } do
      conn = get(conn, ~p"/media_profiles/#{media_profile}/edit")
      assert html_response(conn, 200) =~ "Editing \"#{media_profile.name}\""
    end
  end

  describe "update media_profile" do
    setup [:create_media_profile]

    test "redirects when data is valid", %{conn: conn, media_profile: media_profile} do
      conn = put(conn, ~p"/media_profiles/#{media_profile}", media_profile: @update_attrs)
      assert redirected_to(conn) == ~p"/media_profiles/#{media_profile}"

      conn = get(conn, ~p"/media_profiles/#{media_profile}")
      assert html_response(conn, 200) =~ "some updated name"
    end

    test "persists the YouTube Super Resolution preference", %{conn: conn, media_profile: media_profile} do
      conn =
        put(conn, ~p"/media_profiles/#{media_profile}",
          media_profile: Map.put(@update_attrs, :ignore_youtube_super_resolution, true)
        )

      assert redirected_to(conn) == ~p"/media_profiles/#{media_profile}"
      assert Repo.reload!(media_profile).ignore_youtube_super_resolution
    end

    test "renders errors when data is invalid", %{conn: conn, media_profile: media_profile} do
      conn = put(conn, ~p"/media_profiles/#{media_profile}", media_profile: @invalid_attrs)
      assert html_response(conn, 200) =~ "Editing \"#{media_profile.name}\""
    end

    test "marks a staged reconcile plan stale", %{conn: conn, media_profile: media_profile} do
      {:ok, plan} = Pinchflat.Reconciliation.create_plan(%{mode: :local, status: :ready})

      put(conn, ~p"/media_profiles/#{media_profile}", media_profile: @update_attrs)

      assert Pinchflat.Reconciliation.get_plan!(plan.id).status == :stale
    end
  end

  describe "delete media_profile in all cases" do
    setup [:create_media_profile]

    test "redirects to the media_profiles page", %{conn: conn, media_profile: media_profile} do
      conn = delete(conn, ~p"/media_profiles/#{media_profile}")

      assert redirected_to(conn) == ~p"/media_profiles"
    end

    test "sets marked_for_deletion_at", %{conn: conn, media_profile: media_profile} do
      delete(conn, ~p"/media_profiles/#{media_profile}")
      assert Repo.reload!(media_profile).marked_for_deletion_at
    end
  end

  describe "delete media_profile when just deleting the records" do
    setup [:create_media_profile]

    test "enqueues a job without the delete_files arg", %{conn: conn, media_profile: media_profile} do
      delete(conn, ~p"/media_profiles/#{media_profile}")

      assert [%{args: %{"delete_files" => false}}] = all_enqueued(worker: MediaProfileDeletionWorker)
    end
  end

  describe "delete media_profile when deleting the records and files" do
    setup [:create_media_profile]

    setup do
      stub(UserScriptRunnerMock, :run, fn _event_type, _data -> {:ok, "", 0} end)

      :ok
    end

    test "enqueues a job with the delete_files arg", %{conn: conn, media_profile: media_profile} do
      delete(conn, ~p"/media_profiles/#{media_profile}?delete_files=true")

      assert [%{args: %{"delete_files" => true}}] = all_enqueued(worker: MediaProfileDeletionWorker)
    end
  end

  defp create_media_profile(_) do
    media_profile = media_profile_fixture()

    %{media_profile: media_profile}
  end
end
