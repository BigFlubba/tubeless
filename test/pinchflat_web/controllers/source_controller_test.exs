defmodule PinchflatWeb.SourceControllerTest do
  use PinchflatWeb.ConnCase

  import Ecto.Query
  import Pinchflat.MediaFixtures
  import Pinchflat.TasksFixtures
  import Pinchflat.SourcesFixtures
  import Pinchflat.ProfilesFixtures

  alias Pinchflat.Repo
  alias Pinchflat.Settings
  alias Pinchflat.Media.FileSyncingWorker
  alias Pinchflat.Sources.SourceDeletionWorker
  alias Pinchflat.Downloading.MediaDownloadWorker
  alias Pinchflat.Metadata.SourceMetadataStorageWorker
  alias Pinchflat.SlowIndexing.MediaCollectionIndexingWorker

  setup do
    media_profile = media_profile_fixture()
    Settings.set(onboarding: false)

    {
      :ok,
      %{
        create_attrs: %{
          media_profile_id: media_profile.id,
          collection_type: "channel",
          original_url: "https://www.youtube.com/source/abc123"
        },
        update_attrs: %{
          original_url: "https://www.youtube.com/source/321xyz"
        },
        invalid_attrs: %{original_url: nil, media_profile_id: nil}
      }
    }
  end

  describe "show" do
    test "renders the source header with metrics and status", %{conn: conn} do
      source = source_fixture()
      conn = get(conn, ~p"/sources/#{source}")
      html = html_response(conn, 200)

      assert html =~ source.custom_name
      assert html =~ "Downloaded"
      assert html =~ "Pending"
      assert html =~ "Last checked"
      assert html =~ "Next check"
    end

    test "shows a Paused status for a disabled source", %{conn: conn} do
      source = source_fixture(%{enabled: false})
      conn = get(conn, ~p"/sources/#{source}")

      assert html_response(conn, 200) =~ "Paused"
    end

    test "shows a Resume button for a disabled source and Pause for an enabled one", %{conn: conn} do
      paused = source_fixture(%{enabled: false})
      assert get(conn, ~p"/sources/#{paused}") |> html_response(200) =~ "Resume source"

      active = source_fixture(%{enabled: true})
      assert get(conn, ~p"/sources/#{active}") |> html_response(200) =~ "Pause source"
    end

    test "collapses a YouTube handle URL to just the handle as the link label", %{conn: conn} do
      source = source_fixture(%{original_url: "https://www.youtube.com/@some-fake-channel"})
      html = get(conn, ~p"/sources/#{source}") |> html_response(200)

      # Visible label is the bare handle...
      assert html =~ ~r/>\s*@some-fake-channel/
      # ...but the link still points at the full original URL
      assert html =~ ~s(href="https://www.youtube.com/@some-fake-channel")
    end

    test "renders for a source with no media items", %{conn: conn} do
      source = source_fixture()
      conn = get(conn, ~p"/sources/#{source}")

      assert html_response(conn, 200) =~ source.custom_name
    end
  end

  describe "show - blocking conditions banner" do
    test "renders no banner for a healthy source", %{conn: conn} do
      source = source_fixture(%{enabled: true, last_indexed_at: DateTime.utc_now()})
      media_item_fixture(%{source_id: source.id, media_filepath: "/downloads/video.mp4"})

      html = conn |> get(~p"/sources/#{source}") |> html_response(200)

      refute html =~ "This source is paused, so Tubeless"
      refute html =~ "hasn&#39;t been indexed yet"
    end

    test "renders no banner for a paused source", %{conn: conn} do
      # The header pill already says Paused; a banner would only restate it
      source = source_fixture(%{enabled: false, download_media: false, last_indexed_at: nil})

      html = conn |> get(~p"/sources/#{source}") |> html_response(200)

      refute html =~ "set to index only"
      refute html =~ "hasn&#39;t been indexed yet"
    end

    test "names the blocking condition and links to the fix", %{conn: conn} do
      source = source_fixture(%{enabled: true, download_media: false, last_indexed_at: DateTime.utc_now()})
      media_item_fixture(%{source_id: source.id, media_filepath: nil})

      html = conn |> get(~p"/sources/#{source}") |> html_response(200)

      assert html =~ "set to index only"
      assert html =~ "Edit source"
    end

    test "shows only the most fundamental condition when several apply", %{conn: conn} do
      source = source_fixture(%{enabled: true, download_media: false, last_indexed_at: nil})

      html = conn |> get(~p"/sources/#{source}") |> html_response(200)

      assert html =~ "set to index only"
      refute html =~ "hasn&#39;t been indexed yet"
    end

    test "explains an index that has never run and offers to start one", %{conn: conn} do
      source = source_fixture(%{enabled: true, last_indexed_at: nil})

      html = conn |> get(~p"/sources/#{source}") |> html_response(200)

      assert html =~ "hasn&#39;t been indexed yet"
      # The header always carries one index button; the banner adds a second
      assert index_button_count(html, source) == 2
    end

    test "says to wait, with no button, when the first index is already queued", %{conn: conn} do
      source = source_fixture(%{enabled: true, last_indexed_at: nil})

      {:ok, job} = %{"id" => source.id} |> MediaCollectionIndexingWorker.new() |> Oban.insert()
      set_job_state(job.id, "scheduled", [])
      Pinchflat.Tasks.create_task(job, source)

      html = conn |> get(~p"/sources/#{source}") |> html_response(200)

      assert html =~ "being indexed for the first time"
      refute html =~ "hasn&#39;t been indexed yet"
      # Only the header's button — no banner prompt to enqueue a duplicate of the
      # job that's already on its way
      assert index_button_count(html, source) == 1
    end

    defp index_button_count(html, source) do
      length(String.split(html, ~s(href="/sources/#{source.id}/check_for_new_videos"))) - 1
    end
  end

  describe "show - details tab" do
    test "renders grouped, human-labelled settings instead of the raw attribute dump", %{conn: conn} do
      source = source_fixture()
      html = conn |> get(~p"/sources/#{source}") |> html_response(200)

      refute html =~ "Raw Attributes"

      for group <- ["Identity", "Indexing", "Filters", "Storage"] do
        assert html =~ group
      end

      # Human sentence-case labels with help text, not snake_case field names
      # (the snake_case names survive only inside the Raw JSON view)
      assert html =~ "Index frequency"
      assert html =~ "How often the full channel or playlist is re-read"
    end

    test "renders friendly values for enum-ish and durational fields", %{conn: conn} do
      source =
        source_fixture(%{
          index_frequency_minutes: 60 * 24,
          fast_index: false,
          min_duration_seconds: 120,
          retention_period_days: 30
        })

      html = conn |> get(~p"/sources/#{source}") |> html_response(200)

      assert html =~ "Daily (recommended)"
      assert html =~ "2:00"
      assert html =~ "30 days"
    end

    test "marks unset fields and offers a toggle to reveal them", %{conn: conn} do
      source = source_fixture(%{title_filter_regex: nil, min_duration_seconds: nil})
      html = conn |> get(~p"/sources/#{source}") |> html_response(200)

      assert html =~ "Show unset fields"
      assert html =~ "Not set"
      # Unset rows are in the DOM but hidden until the toggle is flipped
      assert html =~ ~s(style="display: none")
    end

    test "shows internal identifiers and filepaths with a raw JSON view", %{conn: conn} do
      source = source_fixture()
      html = conn |> get(~p"/sources/#{source}") |> html_response(200)

      assert html =~ "Internal"
      assert html =~ "Raw JSON"
      assert html =~ source.uuid
      assert html =~ source.collection_id
    end
  end

  describe "show - activity tab" do
    test "renders an empty state for a source with no activity", %{conn: conn} do
      source = source_fixture()
      html = conn |> get(~p"/sources/#{source}") |> html_response(200)

      assert html =~ "Nothing yet"
    end

    test "describes each entry in plain language rather than by worker module", %{conn: conn} do
      source = source_fixture()
      task = task_fixture(source_id: source.id)
      set_job_state(task.job_id, "completed", worker: "Pinchflat.FastIndexing.FastIndexingWorker")

      html = conn |> get(~p"/sources/#{source}") |> html_response(200)

      assert html =~ "Checked for new videos"
      assert html =~ "Completed"
      refute html =~ "FastIndexingWorker"
    end

    test "includes activity from the source's media items, not just the source", %{conn: conn} do
      source = source_fixture()
      media_item = media_item_fixture(source_id: source.id, title: "A Specific Video")
      task = task_fixture(source_id: nil, media_item_id: media_item.id)
      set_job_state(task.job_id, "completed", worker: "Pinchflat.Downloading.MediaDownloadWorker")

      html = conn |> get(~p"/sources/#{source}") |> html_response(200)

      assert html =~ "Downloaded media"
      assert html =~ "A Specific Video"
    end

    test "reports how long a finished job took", %{conn: conn} do
      source = source_fixture()
      task = task_fixture(source_id: source.id)
      started = DateTime.add(DateTime.utc_now(), -90, :second)

      set_job_state(task.job_id, "completed",
        attempted_at: started,
        completed_at: DateTime.add(started, 90, :second)
      )

      html = conn |> get(~p"/sources/#{source}") |> html_response(200)

      assert html =~ "took 1m 30s"
    end

    test "pins an unresolved failure and badges the tab", %{conn: conn} do
      source = source_fixture()
      task = task_fixture(source_id: source.id)

      set_job_state(task.job_id, "discarded",
        attempt: 3,
        errors: [%{"error" => "ERROR: Video unavailable\n  at some/stack/trace.ex:12"}]
      )

      html = conn |> get(~p"/sources/#{source}") |> html_response(200)

      assert html =~ "Needs attention"
      assert html =~ "1 unresolved"
      # The headline is on screen, the stacktrace behind a disclosure
      assert html =~ "ERROR: Video unavailable"
      assert html =~ "Show detail"
      assert html =~ "at some/stack/trace.ex:12"
      # Danger-tinted count badge on the tab label
      assert html =~ ~s(title="Needs attention")
    end

    test "does not pin anything when every job succeeded", %{conn: conn} do
      source = source_fixture()
      task = task_fixture(source_id: source.id)
      set_job_state(task.job_id, "completed", [])

      html = conn |> get(~p"/sources/#{source}") |> html_response(200)

      refute html =~ "Needs attention"
    end

    test "labels a not-yet-run job as scheduled rather than as history", %{conn: conn} do
      source = source_fixture()
      task = task_fixture(source_id: source.id)

      set_job_state(task.job_id, "scheduled",
        worker: "Pinchflat.SlowIndexing.MediaCollectionIndexingWorker",
        scheduled_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      )

      html = conn |> get(~p"/sources/#{source}") |> html_response(200)

      assert html =~ "Scheduled for"
      assert html =~ "Indexed the collection"
    end
  end

  describe "show - podcast tab" do
    test "is rendered for every source, since the dynamic feed always works", %{conn: conn} do
      source = source_fixture()
      html = conn |> get(~p"/sources/#{source}") |> html_response(200)

      assert html =~ "setTabByName(&#39;podcast&#39;)"
      assert html =~ "/sources/#{source.uuid}/feed.xml"
    end

    test "tells a non-podcast source how to turn on the static feed", %{conn: conn} do
      source = source_fixture()
      html = conn |> get(~p"/sources/#{source}") |> html_response(200)

      assert html =~ "isn't published as a static podcast"
      assert html =~ "Publish as Podcast"
    end

    test "is rendered for a source whose media profile publishes as a podcast", %{conn: conn} do
      media_profile = media_profile_fixture(%{podcast_enabled: true})
      source = source_fixture(%{media_profile_id: media_profile.id})
      html = conn |> get(~p"/sources/#{source}") |> html_response(200)

      assert html =~ "setTabByName(&#39;podcast&#39;)"
      assert html =~ "Subscribe"
      assert html =~ "Served by Tubeless"
      assert html =~ "Served by your own web server"
    end

    test "always offers the dynamic feed Tubeless serves itself", %{conn: conn} do
      media_profile = media_profile_fixture(%{podcast_enabled: true})
      source = source_fixture(%{media_profile_id: media_profile.id})
      html = conn |> get(~p"/sources/#{source}") |> html_response(200)

      # Available regardless of whether the static export has run or is configured
      assert html =~ "/sources/#{source.uuid}/feed.xml"
    end

    test "explains the missing URL base rather than rendering an empty tab", %{conn: conn} do
      media_profile = media_profile_fixture(%{podcast_enabled: true})
      source = source_fixture(%{media_profile_id: media_profile.id})
      Settings.set(podcast_url_base: nil)

      html = conn |> get(~p"/sources/#{source}") |> html_response(200)

      assert html =~ "Podcast URL Base setting"
    end
  end

  describe "index" do
    # Most of the tests are in `index_table_list_test.exs`
    test "returns 200", %{conn: conn} do
      conn = get(conn, ~p"/sources")
      assert html_response(conn, 200) =~ "Sources"
    end
  end

  describe "new source" do
    test "renders form", %{conn: conn} do
      conn = get(conn, ~p"/sources/new")
      assert html_response(conn, 200) =~ "New Source"
    end

    test "renders correct layout when onboarding", %{conn: conn} do
      Settings.set(onboarding: true)
      conn = get(conn, ~p"/sources/new")

      refute html_response(conn, 200) =~ "MENU"
    end

    test "preloads some attributes when using a template", %{conn: conn} do
      source = source_fixture(custom_name: "My first source", download_cutoff_date: "2021-01-01")

      conn = get(conn, ~p"/sources/new", %{"template_id" => source.id})
      assert html_response(conn, 200) =~ "New Source"
      assert html_response(conn, 200) =~ "2021-01-01"
      refute html_response(conn, 200) =~ source.custom_name
    end
  end

  describe "create source" do
    test "redirects to show when data is valid", %{conn: conn, create_attrs: create_attrs} do
      expect(YtDlpRunnerMock, :run, 1, &runner_function_mock/5)
      conn = post(conn, ~p"/sources", source: create_attrs)

      assert %{id: id} = redirected_params(conn)
      assert redirected_to(conn) == ~p"/sources/#{id}"

      conn = get(conn, ~p"/sources/#{id}")
      assert html_response(conn, 200) =~ "Source"
    end

    test "renders errors when data is invalid", %{conn: conn, invalid_attrs: invalid_attrs} do
      conn = post(conn, ~p"/sources", source: invalid_attrs)
      assert html_response(conn, 200) =~ "New Source"
    end

    test "redirects to onboarding when onboarding", %{conn: conn, create_attrs: create_attrs} do
      expect(YtDlpRunnerMock, :run, 1, &runner_function_mock/5)

      Settings.set(onboarding: true)
      conn = post(conn, ~p"/sources", source: create_attrs)

      assert redirected_to(conn) == ~p"/?onboarding=1"
    end

    test "renders correct layout on error when onboarding", %{conn: conn, invalid_attrs: invalid_attrs} do
      Settings.set(onboarding: true)
      conn = post(conn, ~p"/sources", source: invalid_attrs)

      refute html_response(conn, 200) =~ "MENU"
    end
  end

  describe "edit source" do
    setup [:create_source]

    test "renders form for editing chosen source", %{conn: conn, source: source} do
      conn = get(conn, ~p"/sources/#{source}/edit")
      assert html_response(conn, 200) =~ "Editing \"#{source.custom_name}\""
    end
  end

  describe "update source" do
    setup [:create_source]

    test "redirects when data is valid", %{conn: conn, source: source, update_attrs: update_attrs} do
      expect(YtDlpRunnerMock, :run, 1, &runner_function_mock/5)

      conn = put(conn, ~p"/sources/#{source}", source: update_attrs)
      assert redirected_to(conn) == ~p"/sources/#{source}"

      conn = get(conn, ~p"/sources/#{source}")
      assert html_response(conn, 200) =~ "https://www.youtube.com/source/321xyz"
    end

    test "renders errors when data is invalid", %{
      conn: conn,
      source: source,
      invalid_attrs: invalid_attrs
    } do
      conn = put(conn, ~p"/sources/#{source}", source: invalid_attrs)
      assert html_response(conn, 200) =~ "Editing \"#{source.custom_name}\""
    end

    test "marks a staged reconcile plan stale", %{conn: conn, source: source, update_attrs: update_attrs} do
      expect(YtDlpRunnerMock, :run, 1, &runner_function_mock/5)
      {:ok, plan} = Pinchflat.Reconciliation.create_plan(%{mode: :local, status: :ready})

      put(conn, ~p"/sources/#{source}", source: update_attrs)

      assert Pinchflat.Reconciliation.get_plan!(plan.id).status == :stale
    end
  end

  describe "delete source in all cases" do
    setup [:create_source]

    test "redirects to the sources page", %{conn: conn, source: source} do
      conn = delete(conn, ~p"/sources/#{source}")
      assert redirected_to(conn) == ~p"/sources"
    end

    test "sets marked_for_deletion_at", %{conn: conn, source: source} do
      delete(conn, ~p"/sources/#{source}")
      assert Repo.reload!(source).marked_for_deletion_at
    end
  end

  describe "delete source when just deleting the records" do
    setup [:create_source]

    test "enqueues a job without the delete_files arg", %{conn: conn, source: source} do
      delete(conn, ~p"/sources/#{source}")

      assert [%{args: %{"delete_files" => false}}] = all_enqueued(worker: SourceDeletionWorker)
    end
  end

  describe "delete source when deleting the records and files" do
    setup [:create_source]

    test "enqueues a job without the delete_files arg", %{conn: conn, source: source} do
      delete(conn, ~p"/sources/#{source}?delete_files=true")

      assert [%{args: %{"delete_files" => true}}] = all_enqueued(worker: SourceDeletionWorker)
    end
  end

  describe "force_download_pending" do
    test "enqueues pending download tasks", %{conn: conn} do
      source = source_fixture()
      _media_item = media_item_fixture(%{source_id: source.id, media_filepath: nil})

      assert [] = all_enqueued(worker: MediaDownloadWorker)
      post(conn, ~p"/sources/#{source.id}/force_download_pending")
      assert [_] = all_enqueued(worker: MediaDownloadWorker)
    end

    test "redirects to the source page", %{conn: conn} do
      source = source_fixture()

      conn = post(conn, ~p"/sources/#{source.id}/force_download_pending")
      assert redirected_to(conn) == ~p"/sources/#{source.id}"
    end
  end

  describe "force_redownload" do
    test "enqueues re-download tasks", %{conn: conn} do
      source = source_fixture()
      _media_item = media_item_fixture(source_id: source.id, media_downloaded_at: now())

      assert [] = all_enqueued(worker: MediaDownloadWorker)
      post(conn, ~p"/sources/#{source.id}/force_redownload")
      assert [_] = all_enqueued(worker: MediaDownloadWorker)
    end

    test "redirects to the source page", %{conn: conn} do
      source = source_fixture()

      conn = post(conn, ~p"/sources/#{source.id}/force_redownload")
      assert redirected_to(conn) == ~p"/sources/#{source.id}"
    end
  end

  describe "force_index" do
    test "forces an index", %{conn: conn} do
      source = source_fixture()

      assert [] = all_enqueued(worker: MediaCollectionIndexingWorker)
      post(conn, ~p"/sources/#{source.id}/force_index")
      assert [_] = all_enqueued(worker: MediaCollectionIndexingWorker)
    end

    test "forces an index even if one wouldn't normally run", %{conn: conn} do
      source = source_fixture(index_frequency_minutes: 0, last_indexed_at: DateTime.utc_now())

      post(conn, ~p"/sources/#{source.id}/force_index")
      assert [job] = all_enqueued(worker: MediaCollectionIndexingWorker)
      assert job.args == %{"id" => source.id, "force" => true}
    end

    test "deletes pending indexing tasks", %{conn: conn} do
      source = source_fixture()
      {:ok, task} = MediaCollectionIndexingWorker.kickoff_with_task(source)
      job = Repo.preload(task, :job).job

      assert job.state == "available"
      post(conn, ~p"/sources/#{source.id}/force_index")
      assert Repo.reload!(job).state == "cancelled"
    end

    test "redirects to the source page", %{conn: conn} do
      source = source_fixture()

      conn = post(conn, ~p"/sources/#{source.id}/force_index")
      assert redirected_to(conn) == ~p"/sources/#{source.id}"
    end

    test "refuses to force an index for a paused source", %{conn: conn} do
      source = source_fixture(%{enabled: false})

      post(conn, ~p"/sources/#{source.id}/force_index")
      assert [] = all_enqueued(worker: MediaCollectionIndexingWorker)
    end
  end

  describe "image" do
    test "serves a source image that exists on disk", %{conn: conn} do
      source = source_with_metadata_attachments()

      conn = get(conn, ~p"/sources/#{source.id}/image/poster")
      assert conn.status == 200
      assert conn |> get_resp_header("content-type") |> hd() =~ "image/jpeg"
    end

    test "404s when the source has no image of that type", %{conn: conn} do
      source = source_fixture()

      conn = get(conn, ~p"/sources/#{source.id}/image/banner")
      assert conn.status == 404
    end

    test "404s for an unknown image type", %{conn: conn} do
      source = source_with_metadata_attachments()

      conn = get(conn, ~p"/sources/#{source.id}/image/bogus")
      assert conn.status == 404
    end

    test "404s (does not serve) a filepath outside the managed directories", %{conn: conn} do
      # Simulate a filepath that was somehow persisted pointing outside the
      # app-managed media/metadata dirs — the route must refuse to serve it even
      # though the file exists and is readable.
      outside_path = Path.join(System.tmp_dir!(), "pinchflat-secret-#{:rand.uniform(1_000_000)}.jpg")
      File.write!(outside_path, "not really an image")
      on_exit(fn -> File.rm(outside_path) end)

      source = source_fixture()

      source
      |> Ecto.Changeset.change(banner_filepath: outside_path)
      |> Repo.update!()

      conn = get(conn, ~p"/sources/#{source.id}/image/banner")
      assert conn.status == 404
    end

    test "404s for a path that only reaches outside via a symlink", %{conn: conn} do
      # The prefix check has to resolve symlinks, not just normalize `..` — a link
      # planted inside the media directory otherwise passes it while reading an
      # arbitrary file.
      outside_path = Path.join(System.tmp_dir!(), "pinchflat-secret-#{:rand.uniform(1_000_000)}.jpg")
      File.write!(outside_path, "not really an image")

      link_path = Path.join(Application.get_env(:pinchflat, :media_directory), "banner.jpg")
      File.mkdir_p!(Path.dirname(link_path))
      File.ln_s!(outside_path, link_path)

      on_exit(fn ->
        File.rm(outside_path)
        File.rm(link_path)
      end)

      source = source_fixture()

      source
      |> Ecto.Changeset.change(banner_filepath: link_path)
      |> Repo.update!()

      conn = get(conn, ~p"/sources/#{source.id}/image/banner")
      assert conn.status == 404
    end
  end

  describe "toggle_enabled" do
    test "pauses an enabled source", %{conn: conn} do
      source = source_fixture(%{enabled: true})

      conn = post(conn, ~p"/sources/#{source.id}/toggle_enabled")
      assert redirected_to(conn) == ~p"/sources/#{source.id}"
      refute Repo.reload!(source).enabled
    end

    test "resumes a disabled source", %{conn: conn} do
      source = source_fixture(%{enabled: false})

      post(conn, ~p"/sources/#{source.id}/toggle_enabled")
      assert Repo.reload!(source).enabled
    end
  end

  describe "check_for_new_videos" do
    test "enqueues an incremental (non-forced) index", %{conn: conn} do
      source = source_fixture()

      assert [] = all_enqueued(worker: MediaCollectionIndexingWorker)
      post(conn, ~p"/sources/#{source.id}/check_for_new_videos")
      assert [job] = all_enqueued(worker: MediaCollectionIndexingWorker)
      assert job.args == %{"id" => source.id}
    end

    test "enqueues immediately even for a recently-indexed source", %{conn: conn} do
      source = source_fixture(index_frequency_minutes: 60, last_indexed_at: DateTime.utc_now())

      post(conn, ~p"/sources/#{source.id}/check_for_new_videos")
      assert [job] = all_enqueued(worker: MediaCollectionIndexingWorker)
      assert DateTime.diff(job.scheduled_at, DateTime.utc_now(), :second) <= 1
    end

    test "redirects to the source page", %{conn: conn} do
      source = source_fixture()

      conn = post(conn, ~p"/sources/#{source.id}/check_for_new_videos")
      assert redirected_to(conn) == ~p"/sources/#{source.id}"
    end

    test "refuses to enqueue an index for a paused source", %{conn: conn} do
      source = source_fixture(%{enabled: false})

      conn = post(conn, ~p"/sources/#{source.id}/check_for_new_videos")
      assert [] = all_enqueued(worker: MediaCollectionIndexingWorker)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Resume this source"
    end

    test "does not interrupt an index that is already executing", %{conn: conn} do
      source = source_fixture()
      {:ok, job} = Oban.insert(MediaCollectionIndexingWorker.new(%{"id" => source.id}))
      task = task_fixture(source_id: source.id, job_id: job.id)
      Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id, update: [set: [state: "executing"]]), [])

      conn = post(conn, ~p"/sources/#{source.id}/check_for_new_videos")

      assert Repo.reload!(task)
      assert Repo.reload!(job).state == "executing"
      assert [] = all_enqueued(worker: MediaCollectionIndexingWorker)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "already being indexed"
    end
  end

  describe "force_metadata_refresh" do
    test "forces a metadata refresh", %{conn: conn} do
      source = source_fixture()

      assert [] = all_enqueued(worker: SourceMetadataStorageWorker)
      post(conn, ~p"/sources/#{source.id}/force_metadata_refresh")
      assert [_] = all_enqueued(worker: SourceMetadataStorageWorker)
    end

    test "redirects to the source page", %{conn: conn} do
      source = source_fixture()

      conn = post(conn, ~p"/sources/#{source.id}/force_metadata_refresh")
      assert redirected_to(conn) == ~p"/sources/#{source.id}"
    end
  end

  describe "sync_files_on_disk" do
    test "forces a file sync", %{conn: conn} do
      source = source_fixture()

      assert [] = all_enqueued(worker: FileSyncingWorker)
      post(conn, ~p"/sources/#{source.id}/sync_files_on_disk")
      assert [_] = all_enqueued(worker: FileSyncingWorker)
    end

    test "redirects to the source page", %{conn: conn} do
      source = source_fixture()

      conn = post(conn, ~p"/sources/#{source.id}/sync_files_on_disk")
      assert redirected_to(conn) == ~p"/sources/#{source.id}"
    end
  end

  defp create_source(_) do
    source = source_fixture()
    media_item = media_item_with_attachments(%{source_id: source.id})

    %{source: source, media_item: media_item}
  end

  defp runner_function_mock(_url, :get_source_details, _opts, _ot, _addl) do
    {
      :ok,
      Phoenix.json_library().encode!(%{
        channel: "some channel name",
        channel_id: "some_channel_id_#{:rand.uniform(1_000_000)}",
        playlist_id: "some_playlist_id_#{:rand.uniform(1_000_000)}",
        playlist_title: "some playlist name"
      })
    }
  end

  defp set_job_state(job_id, state, extra_fields) do
    Repo.update_all(
      from(j in Oban.Job, where: j.id == ^job_id),
      set: [{:state, state} | extra_fields]
    )
  end
end
