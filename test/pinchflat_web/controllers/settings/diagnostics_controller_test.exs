defmodule PinchflatWeb.Settings.DiagnosticsControllerTest do
  use PinchflatWeb.ConnCase

  import Ecto.Query, warn: false
  import Pinchflat.SourcesFixtures

  alias Pinchflat.Repo
  alias Pinchflat.JobFixtures.TestJobWorker
  alias Pinchflat.FastIndexing.FastIndexingWorker

  describe "show" do
    test "renders the page", %{conn: conn} do
      conn = get(conn, ~p"/diagnostics")

      assert html_response(conn, 200) =~ "Diagnostics"
    end
  end

  describe "reset_retryable_jobs" do
    test "resets retryable jobs and redirects with a count", %{conn: conn} do
      job = job_in_state("retryable")

      conn = post(conn, ~p"/diagnostics/reset_retryable_jobs")

      assert redirected_to(conn) == ~p"/diagnostics"
      assert conn.assigns[:flash]["info"] =~ "Reset 1 retryable job(s)"
      assert %{state: "available"} = Repo.reload(job)
    end
  end

  describe "reset_job" do
    test "resets a retryable job and redirects", %{conn: conn} do
      job = job_in_state("retryable")

      conn = post(conn, ~p"/diagnostics/reset_job/#{job.id}")

      assert redirected_to(conn) == ~p"/diagnostics"
      assert conn.assigns[:flash]["info"] =~ "has been reset"
      assert %{state: "available"} = Repo.reload(job)
    end

    test "shows an error when the job cannot be reset", %{conn: conn} do
      job = job_in_state("executing")

      conn = post(conn, ~p"/diagnostics/reset_job/#{job.id}")

      assert redirected_to(conn) == ~p"/diagnostics"
      assert conn.assigns[:flash]["error"] =~ "could not be reset"
      assert %{state: "executing"} = Repo.reload(job)
    end

    test "shows an error for a non-numeric job id", %{conn: conn} do
      conn = post(conn, ~p"/diagnostics/reset_job/bogus")

      assert redirected_to(conn) == ~p"/diagnostics"
      assert conn.assigns[:flash]["error"] =~ "not a valid job ID"
    end
  end

  describe "requeue_job" do
    test "requeues a job and redirects", %{conn: conn} do
      job = job_in_state("executing")

      conn = post(conn, ~p"/diagnostics/requeue_job/#{job.id}")

      assert redirected_to(conn) == ~p"/diagnostics"
      assert conn.assigns[:flash]["info"] =~ "was requeued"
      assert %{state: "cancelled"} = Repo.reload(job)
    end

    test "shows an error when the job does not exist", %{conn: conn} do
      conn = post(conn, ~p"/diagnostics/requeue_job/12345678")

      assert redirected_to(conn) == ~p"/diagnostics"
      assert conn.assigns[:flash]["error"] =~ "could not be requeued"
    end

    test "shows an error for a non-numeric job id", %{conn: conn} do
      conn = post(conn, ~p"/diagnostics/requeue_job/bogus")

      assert redirected_to(conn) == ~p"/diagnostics"
      assert conn.assigns[:flash]["error"] =~ "not a valid job ID"
    end
  end

  describe "delete_job" do
    test "deletes a discarded job and redirects", %{conn: conn} do
      job = job_in_state("discarded")

      conn = post(conn, ~p"/diagnostics/delete_job/#{job.id}")

      assert redirected_to(conn) == ~p"/diagnostics"
      assert conn.assigns[:flash]["info"] =~ "has been deleted"
      assert Repo.reload(job) == nil
    end

    test "shows an error when the job is not discarded", %{conn: conn} do
      job = job_in_state("available")

      conn = post(conn, ~p"/diagnostics/delete_job/#{job.id}")

      assert redirected_to(conn) == ~p"/diagnostics"
      assert conn.assigns[:flash]["error"] =~ "could not be deleted"
      assert Repo.reload(job)
    end

    test "shows an error for a non-numeric job id", %{conn: conn} do
      conn = post(conn, ~p"/diagnostics/delete_job/bogus")

      assert redirected_to(conn) == ~p"/diagnostics"
      assert conn.assigns[:flash]["error"] =~ "not a valid job ID"
    end
  end

  describe "vacuum_database" do
    test "enqueues a maintenance job and redirects", %{conn: conn} do
      conn = post(conn, ~p"/diagnostics/vacuum_database")

      assert redirected_to(conn) == ~p"/diagnostics"
      assert conn.assigns[:flash]["info"] =~ "Database compaction queued"
      assert [_] = all_enqueued(worker: Pinchflat.Diagnostics.DatabaseMaintenanceWorker)
    end

    test "reports when a maintenance job is already queued", %{conn: conn} do
      post(conn, ~p"/diagnostics/vacuum_database")
      conn = post(conn, ~p"/diagnostics/vacuum_database")

      assert redirected_to(conn) == ~p"/diagnostics"
      assert conn.assigns[:flash]["info"] =~ "already queued or running"
      assert [_] = all_enqueued(worker: Pinchflat.Diagnostics.DatabaseMaintenanceWorker)
    end
  end

  describe "toggle_scheduled_compaction" do
    test "turns scheduled compaction on", %{conn: conn} do
      conn = post(conn, ~p"/diagnostics/toggle_scheduled_compaction")

      assert redirected_to(conn) == ~p"/diagnostics"
      assert conn.assigns[:flash]["info"] =~ "Scheduled compaction turned on"
      assert Pinchflat.Settings.get!(:database_maintenance_enabled) == true
    end

    test "turns scheduled compaction off when it is on", %{conn: conn} do
      Pinchflat.Settings.set(database_maintenance_enabled: true)

      conn = post(conn, ~p"/diagnostics/toggle_scheduled_compaction")

      assert redirected_to(conn) == ~p"/diagnostics"
      assert conn.assigns[:flash]["info"] =~ "Scheduled compaction turned off"
      assert Pinchflat.Settings.get!(:database_maintenance_enabled) == false
    end
  end

  describe "delete_orphaned_job" do
    test "deletes a job pointing at a deleted source and redirects", %{conn: conn} do
      {:ok, job} = Oban.insert(FastIndexingWorker.new(%{"id" => 999_999}))

      conn = post(conn, ~p"/diagnostics/delete_orphaned_job/#{job.id}")

      assert redirected_to(conn) == ~p"/diagnostics"
      assert conn.assigns[:flash]["info"] =~ "has been deleted"
      assert Repo.reload(job) == nil
    end

    test "shows an error when the source still exists", %{conn: conn} do
      source = source_fixture()
      {:ok, job} = Oban.insert(FastIndexingWorker.new(%{"id" => source.id}))

      conn = post(conn, ~p"/diagnostics/delete_orphaned_job/#{job.id}")

      assert redirected_to(conn) == ~p"/diagnostics"
      assert conn.assigns[:flash]["error"] =~ "could not be deleted"
      assert Repo.reload(job)
    end

    test "shows an error for a non-numeric job id", %{conn: conn} do
      conn = post(conn, ~p"/diagnostics/delete_orphaned_job/bogus")

      assert redirected_to(conn) == ~p"/diagnostics"
      assert conn.assigns[:flash]["error"] =~ "not a valid job ID"
    end
  end

  describe "delete_orphaned_jobs" do
    test "deletes all orphaned jobs and redirects with a count", %{conn: conn} do
      {:ok, _a} = Oban.insert(FastIndexingWorker.new(%{"id" => 999_998}))
      {:ok, _b} = Oban.insert(FastIndexingWorker.new(%{"id" => 999_999}))

      conn = post(conn, ~p"/diagnostics/delete_orphaned_jobs")

      assert redirected_to(conn) == ~p"/diagnostics"
      assert conn.assigns[:flash]["info"] =~ "Deleted 2 orphaned job(s)"
    end
  end

  defp job_in_state(state) do
    {:ok, job} = Oban.insert(TestJobWorker.new(%{}))
    Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id), set: [state: state])

    %{job | state: state}
  end
end
