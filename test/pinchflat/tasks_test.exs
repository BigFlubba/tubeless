defmodule Pinchflat.TasksTest do
  use Pinchflat.DataCase
  import Pinchflat.JobFixtures
  import Pinchflat.TasksFixtures
  import Pinchflat.MediaFixtures
  import Pinchflat.SourcesFixtures

  alias Pinchflat.Tasks
  alias Pinchflat.Tasks.Task
  alias Pinchflat.JobFixtures.TestJobWorker

  @invalid_attrs %{job_id: nil}
  # A second worker name, so two tasks on the same source count as two distinct
  # pieces of work rather than two attempts at the same one
  @fast_indexing_worker "Pinchflat.FastIndexing.FastIndexingWorker"

  describe "schema" do
    test "deletes a task when the job gets deleted" do
      task = Repo.preload(task_fixture(), [:job])

      {:ok, _} = Repo.delete(task.job)

      assert_raise Ecto.NoResultsError, fn -> Repo.reload!(task) end
    end

    test "does not delete the other record when a job gets deleted" do
      task = Repo.preload(task_fixture(), [:source, :job])

      {:ok, _} = Repo.delete(task.job)

      assert Repo.reload!(task.source)
    end
  end

  describe "list_tasks/0" do
    test "returns all tasks" do
      task = task_fixture()
      assert Tasks.list_tasks() == [task]
    end
  end

  describe "list_tasks_for/3" do
    test "lets you specify which record type/ID to join on" do
      source = source_fixture()
      task = task_fixture(source_id: source.id)

      assert Tasks.list_tasks_for(source, nil, [:available]) == [task]
    end

    test "lets you specify which job states to include" do
      source = source_fixture()
      task = task_fixture(source_id: source.id)

      assert Tasks.list_tasks_for(source, nil, [:available]) == [task]
      assert Tasks.list_tasks_for(source, nil, [:cancelled]) == []
    end

    test "lets you specify which worker to include" do
      source = source_fixture()
      task = task_fixture(source_id: source.id)

      assert Tasks.list_tasks_for(source, "TestJobWorker") == [task]
      assert Tasks.list_tasks_for(source, "FooBarWorker") == []
    end

    test "includes all workers if no worker is specified" do
      source = source_fixture()
      task = task_fixture(source_id: source.id)

      assert Tasks.list_tasks_for(source, nil) == [task]
    end
  end

  describe "list_recent_activity_for_source/2" do
    test "includes tasks attached to the source itself" do
      source = source_fixture()
      task = task_fixture(source_id: source.id)

      assert [%{id: id}] = Tasks.list_recent_activity_for_source(source)
      assert id == task.id
    end

    test "includes tasks attached to the source's media items" do
      source = source_fixture()
      media_item = media_item_fixture(source_id: source.id)
      task = task_fixture(source_id: nil, media_item_id: media_item.id)

      assert [%{id: id}] = Tasks.list_recent_activity_for_source(source)
      assert id == task.id
    end

    test "excludes tasks belonging to other sources" do
      source = source_fixture()
      other_source = source_fixture()
      task_fixture(source_id: other_source.id)
      task_fixture(source_id: nil, media_item_id: media_item_fixture(source_id: other_source.id).id)

      assert [] == Tasks.list_recent_activity_for_source(source)
    end

    test "preloads the job and media item" do
      source = source_fixture()
      media_item = media_item_fixture(source_id: source.id)
      task_fixture(source_id: nil, media_item_id: media_item.id)

      assert [task] = Tasks.list_recent_activity_for_source(source)
      assert %Oban.Job{} = task.job
      assert task.media_item.id == media_item.id
    end

    test "orders by the timestamp the job actually reached, newest first" do
      source = source_fixture()

      old = task_fixture(source_id: source.id)
      recent = task_fixture(source_id: source.id)

      set_job_state(old.job_id, "completed", completed_at: hours_ago(5))
      set_job_state(recent.job_id, "completed", completed_at: hours_ago(1))

      assert [first, second] = Tasks.list_recent_activity_for_source(source)
      assert first.id == recent.id
      assert second.id == old.id
    end

    test "is bounded by the passed limit" do
      source = source_fixture()
      Enum.each(1..3, fn _ -> task_fixture(source_id: source.id) end)

      assert length(Tasks.list_recent_activity_for_source(source, 2)) == 2
    end
  end

  describe "list_unresolved_activity_for_source/2" do
    test "returns retryable and discarded tasks" do
      source = source_fixture()
      retryable = task_fixture(source_id: source.id)
      discarded = task_fixture(source_id: source.id)

      # Different workers, so these are two distinct pieces of work rather than
      # two attempts at the same one
      set_job_state(retryable.job_id, "retryable", attempted_at: hours_ago(2), worker: @fast_indexing_worker)
      set_job_state(discarded.job_id, "discarded", discarded_at: hours_ago(1))

      assert [first, second] = Tasks.list_unresolved_activity_for_source(source)
      assert first.id == discarded.id
      assert second.id == retryable.id
    end

    # A discarded job sticks around for 30 days until Oban prunes it. Once the same
    # work has been re-run successfully it's history, not an open problem - the
    # same "latest per target" rule the header status pill uses.
    test "ignores a failure that a later run of the same work recovered from" do
      source = source_fixture()
      failed = task_fixture(source_id: source.id)
      recovered = task_fixture(source_id: source.id)

      set_job_state(failed.job_id, "discarded", discarded_at: hours_ago(2))
      set_job_state(recovered.job_id, "completed", completed_at: hours_ago(1))

      assert [] == Tasks.list_unresolved_activity_for_source(source)
    end

    test "keeps a failure when the later success was different work" do
      source = source_fixture()
      failed = task_fixture(source_id: source.id)
      unrelated = task_fixture(source_id: source.id)

      set_job_state(failed.job_id, "discarded", discarded_at: hours_ago(2))
      set_job_state(unrelated.job_id, "completed", completed_at: hours_ago(1), worker: @fast_indexing_worker)

      assert [%{id: id}] = Tasks.list_unresolved_activity_for_source(source)
      assert id == failed.id
    end

    test "keeps a media item's failure when a different media item succeeded later" do
      source = source_fixture()
      failed_item = media_item_fixture(source_id: source.id)
      other_item = media_item_fixture(source_id: source.id)

      failed = task_fixture(source_id: nil, media_item_id: failed_item.id)
      succeeded = task_fixture(source_id: nil, media_item_id: other_item.id)

      set_job_state(failed.job_id, "discarded", discarded_at: hours_ago(2))
      set_job_state(succeeded.job_id, "completed", completed_at: hours_ago(1))

      assert [%{id: id}] = Tasks.list_unresolved_activity_for_source(source)
      assert id == failed.id
    end

    test "ignores tasks that completed, are waiting, or were cancelled" do
      source = source_fixture()

      for state <- ~w(completed available scheduled executing cancelled) do
        set_job_state(task_fixture(source_id: source.id).job_id, state, [])
      end

      assert [] == Tasks.list_unresolved_activity_for_source(source)
    end

    test "includes failures of the source's media items' tasks" do
      source = source_fixture()
      media_item = media_item_fixture(source_id: source.id)
      task = task_fixture(source_id: nil, media_item_id: media_item.id)
      set_job_state(task.job_id, "discarded", [])

      assert [%{id: id}] = Tasks.list_unresolved_activity_for_source(source)
      assert id == task.id
    end

    # The whole reason this is its own query rather than a filter over
    # `list_recent_activity_for_source/2`: the failure must survive a run of newer
    # successful jobs that would otherwise push it out of the capped window.
    test "surfaces a failure that is older than a full page of successful jobs" do
      source = source_fixture()
      failure = task_fixture(source_id: source.id)
      set_job_state(failure.job_id, "discarded", discarded_at: hours_ago(100))

      # Successful downloads of other media items - newer, but not a re-run of the
      # work that failed, so they don't resolve it
      Enum.each(1..51, fn hours ->
        media_item = media_item_fixture(source_id: source.id)
        task = task_fixture(source_id: nil, media_item_id: media_item.id)
        set_job_state(task.job_id, "completed", completed_at: hours_ago(hours))
      end)

      recent = Tasks.list_recent_activity_for_source(source, 50)
      refute Enum.any?(recent, &(&1.id == failure.id))

      assert [%{id: id}] = Tasks.list_unresolved_activity_for_source(source)
      assert id == failure.id
    end
  end

  describe "count_in_flight_activity_for_source/1" do
    test "counts non-terminal jobs attached to the source and to its media items" do
      source = source_fixture()
      media_item = media_item_fixture(source_id: source.id)

      set_job_state(task_fixture(source_id: source.id).job_id, "scheduled", [])
      set_job_state(task_fixture(source_id: nil, media_item_id: media_item.id).job_id, "executing", [])
      set_job_state(task_fixture(source_id: source.id).job_id, "retryable", [])

      assert Tasks.count_in_flight_activity_for_source(source) == 3
    end

    test "does not count finished work" do
      source = source_fixture()

      for state <- ~w(completed cancelled discarded) do
        set_job_state(task_fixture(source_id: source.id).job_id, state, [])
      end

      assert Tasks.count_in_flight_activity_for_source(source) == 0
    end

    test "does not count other sources' jobs" do
      source = source_fixture()
      other_source = source_fixture()
      set_job_state(task_fixture(source_id: other_source.id).job_id, "available", [])

      assert Tasks.count_in_flight_activity_for_source(source) == 0
    end
  end

  describe "get_task!/1" do
    test "returns the task with given id" do
      task = task_fixture()
      assert Tasks.get_task!(task.id) == task
    end
  end

  describe "create_task/1" do
    test "creation with valid data creates a task" do
      valid_attrs = %{job_id: job_fixture().id}

      assert {:ok, %Task{} = _task} = Tasks.create_task(valid_attrs)
    end

    test "creation with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Tasks.create_task(@invalid_attrs)
    end

    test "accepts a job and source" do
      job = job_fixture()
      source = source_fixture()

      assert {:ok, %Task{} = task} = Tasks.create_task(job, source)

      assert task.job_id == job.id
      assert task.source_id == source.id
    end

    test "accepts a job and media item" do
      job = job_fixture()
      media_item = media_item_fixture()

      assert {:ok, %Task{} = task} = Tasks.create_task(job, media_item)

      assert task.job_id == job.id
      assert task.media_item_id == media_item.id
    end
  end

  describe "create_job_with_task/2" do
    test "enqueues the given job" do
      media_item = media_item_fixture()

      refute_enqueued(worker: TestJobWorker)
      assert {:ok, %Task{}} = Tasks.create_job_with_task(TestJobWorker.new(%{}), media_item)
      assert_enqueued(worker: TestJobWorker)
    end

    test "creates a task record if successful" do
      source = source_fixture()

      assert {:ok, %Task{} = task} = Tasks.create_job_with_task(TestJobWorker.new(%{}), source)

      assert task.source_id == source.id
    end

    test "returns an error if the job already exists" do
      source = source_fixture()
      job = TestJobWorker.new(%{foo: "bar"}, unique: [period: :infinity])

      assert {:ok, %Task{}} = Tasks.create_job_with_task(job, source)
      assert {:error, :duplicate_job} = Tasks.create_job_with_task(job, source)
    end

    test "returns an error if the job fails to enqueue" do
      source = source_fixture()

      assert {:error, %Ecto.Changeset{}} = Tasks.create_job_with_task(%Ecto.Changeset{}, source)
    end
  end

  describe "delete_task/1" do
    test "deletion deletes the task" do
      task = task_fixture()
      assert {:ok, %Task{}} = Tasks.delete_task(task)
      assert_raise Ecto.NoResultsError, fn -> Tasks.get_task!(task.id) end
    end

    test "deletion also cancels the attached job" do
      task = Repo.preload(task_fixture(), :job)

      assert {:ok, %Task{}} = Tasks.delete_task(task)
      job = Repo.reload!(task.job)

      assert job.state == "cancelled"
    end
  end

  describe "delete_tasks_for/2" do
    test "deletes tasks attached to a source" do
      source = source_fixture()
      task = task_fixture(source_id: source.id)

      assert :ok = Tasks.delete_tasks_for(source)
      assert_raise Ecto.NoResultsError, fn -> Tasks.get_task!(task.id) end
    end

    test "deletes the tasks attached to a media_item" do
      media_item = media_item_fixture()
      task = task_fixture(media_item_id: media_item.id)

      assert :ok = Tasks.delete_tasks_for(media_item)
      assert_raise Ecto.NoResultsError, fn -> Tasks.get_task!(task.id) end
    end

    test "deletion can specify which worker to include" do
      media_item = media_item_fixture()
      task = task_fixture(media_item_id: media_item.id)

      assert :ok = Tasks.delete_tasks_for(media_item, "FooBarWorker")
      assert Repo.reload!(task)

      assert :ok = Tasks.delete_tasks_for(media_item, "TestJobWorker")
      assert_raise Ecto.NoResultsError, fn -> Repo.reload!(task) end
    end

    test "deletion can specify which states to include" do
      source = source_fixture()
      task = task_fixture(source_id: source.id)

      assert :ok = Tasks.delete_tasks_for(source, nil, [:executing])
      assert Repo.reload!(task)

      assert :ok = Tasks.delete_tasks_for(source, nil, [:available])
      assert_raise Ecto.NoResultsError, fn -> Repo.reload!(task) end
    end

    test "deletion does not impact unintended records" do
      source = source_fixture()
      task = task_fixture(source_id: source.id)

      assert :ok = Tasks.delete_tasks_for(source_fixture())
      assert :ok = Tasks.delete_tasks_for(source_fixture(), "FooBarWorker")
      assert :ok = Tasks.delete_tasks_for(source_fixture(), "TestJobWorker")

      assert Repo.reload!(task)
    end
  end

  describe "delete_pending_tasks_for/1" do
    test "deletes pending tasks attached to a source" do
      source = source_fixture()
      task = task_fixture(source_id: source.id)

      assert :ok = Tasks.delete_pending_tasks_for(source)
      assert_raise Ecto.NoResultsError, fn -> Tasks.get_task!(task.id) end
    end

    test "does not delete non-pending tasks" do
      source = source_fixture()
      task = Repo.preload(task_fixture(source_id: source.id), :job)
      :ok = Oban.cancel_job(task.job)

      assert :ok = Tasks.delete_pending_tasks_for(source)
      assert Tasks.get_task!(task.id)
    end

    test "works on media_items" do
      media_item = media_item_fixture()
      pending_task = task_fixture(media_item_id: media_item.id)
      cancelled_task = Repo.preload(task_fixture(media_item_id: media_item.id), :job)
      :ok = Oban.cancel_job(cancelled_task.job)

      assert :ok = Tasks.delete_pending_tasks_for(media_item)
      assert Tasks.get_task!(cancelled_task.id)
      assert_raise Ecto.NoResultsError, fn -> Repo.reload!(pending_task) end
    end

    test "deletion can specify which worker to include" do
      media_item = media_item_fixture()
      task = task_fixture(media_item_id: media_item.id)

      assert :ok = Tasks.delete_pending_tasks_for(media_item, "FooBarWorker")
      assert Repo.reload!(task)

      assert :ok = Tasks.delete_pending_tasks_for(media_item, "TestJobWorker")
      assert_raise Ecto.NoResultsError, fn -> Repo.reload!(task) end
    end

    test "deletion can optionally include executing tasks" do
      source = source_fixture()
      task = task_fixture(source_id: source.id)

      from(Oban.Job, where: [id: ^task.job_id], update: [set: [state: "executing"]])
      |> Repo.update_all([])

      assert :ok = Tasks.delete_pending_tasks_for(source, nil, include_executing: false)
      assert Repo.reload!(task)
      assert :ok = Tasks.delete_pending_tasks_for(source, nil, include_executing: true)
      assert_raise Ecto.NoResultsError, fn -> Repo.reload!(task) end
    end
  end

  describe "change_task/1" do
    test "returns a task changeset" do
      task = task_fixture()
      assert %Ecto.Changeset{} = Tasks.change_task(task)
    end
  end

  defp set_job_state(job_id, state, extra_fields) do
    Repo.update_all(
      from(j in Oban.Job, where: j.id == ^job_id),
      set: [{:state, state} | extra_fields]
    )
  end

  defp hours_ago(hours), do: DateTime.add(DateTime.utc_now(), -hours * 60 * 60, :second)
end
