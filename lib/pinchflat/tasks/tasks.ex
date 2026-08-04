defmodule Pinchflat.Tasks do
  @moduledoc """
  The Tasks context.
  """
  import Ecto.Query, warn: false
  alias Pinchflat.Repo

  alias Pinchflat.Tasks.Task
  alias Pinchflat.Media.MediaItem
  alias Pinchflat.Sources.Source

  @doc """
  Returns the list of tasks. Returns [%Task{}, ...]
  """
  def list_tasks do
    Repo.all(Task)
  end

  @doc """
  Returns the list of tasks for a given record type and ID. Optionally allows you to specify
  which worker or job states to include.

  Returns [%Task{}, ...]
  """
  def list_tasks_for(record, worker_name \\ nil, job_states \\ Oban.Job.states()) do
    stringified_states = Enum.map(job_states, &to_string/1)

    record_type =
      case record do
        %Source{} -> :source_id
        %MediaItem{} -> :media_item_id
      end

    worker_name_finder =
      if worker_name do
        # Workers are the full module name - we want to match on the string ENDING with
        # the passed worker name and it should be preceeded with a . so we aren't matching
        # on a substring. You can pass in more fragments of the worker name if you need
        # to disambiguate. eg: "TestWorker" or "FooBar.TestWorker"
        worker_finder = "%.#{worker_name}"

        dynamic([_t, j], fragment("? LIKE ?", j.worker, ^worker_finder))
      else
        true
      end

    Repo.all(
      from t in Task,
        join: j in assoc(t, :job),
        where: field(t, ^record_type) == ^record.id,
        where: ^worker_name_finder,
        where: j.state in ^stringified_states
    )
  end

  # Job states meaning "not finished, and already gone wrong". `retryable` counts:
  # Oban intends to try again, but the user can see the failure right now.
  @unresolved_states ~w(retryable discarded)
  # Non-terminal states - work that is queued, scheduled, running, or retrying.
  @in_flight_states ~w(available scheduled executing retryable)

  @doc """
  Everything that has happened (or is about to happen) for a source: its own tasks
  plus the tasks of its media items, since downloads attach through `media_item_id`
  rather than `source_id`.

  Ordered newest-first by whichever timestamp the job actually reached, so
  scheduled and executing work sorts above finished history. Bounded by `limit`
  (never an unfiltered scan of `oban_jobs`); the window is additionally capped by
  Oban's Pruner, which deletes completed jobs after 30 days and takes the task
  rows with them via the FK cascade.

  Returns [%Task{}, ...] with `:job` and `:media_item` preloaded.
  """
  def list_recent_activity_for_source(%Source{} = source, limit \\ 50) do
    source
    |> activity_query()
    |> order_by([t, j],
      desc:
        fragment(
          "COALESCE(?, ?, ?, ?, ?, ?)",
          j.completed_at,
          j.cancelled_at,
          j.discarded_at,
          j.attempted_at,
          j.scheduled_at,
          j.inserted_at
        )
    )
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  The source's **currently** failing work, newest failure first: for each piece of
  work — one `{worker, source or media item}` pair — only its *latest* job counts,
  and only if that job is `retryable`/`discarded`.

  Both halves of that matter:

    - Queried independently of `list_recent_activity_for_source/2` rather than
      filtered out of it, so a failure still shows when more than `limit` newer
      jobs have happened since. Otherwise the header pill goes red with nothing on
      the Activity tab explaining why.
    - Superseded by a later success, so a recovered source stops saying "needs
      attention". A discarded job lingers for 30 days until Oban prunes it; if a
      re-run of that same work has since succeeded, the failure is history, not an
      open problem. This is the same "latest per target" rule `Sources.status/1`
      uses for the header pill, so the badge and the pill can't disagree.

  Returns [%Task{}, ...] with `:job` and `:media_item` preloaded.
  """
  def list_unresolved_activity_for_source(%Source{} = source, limit \\ 50) do
    latest_per_target =
      source
      |> activity_query()
      |> exclude(:preload)
      |> group_by([t, j], [j.worker, t.source_id, t.media_item_id])
      |> select([t, j], %{latest_job_id: max(j.id)})

    from(t in Task,
      join: j in assoc(t, :job),
      left_join: mi in MediaItem,
      on: mi.id == t.media_item_id,
      join: latest in subquery(latest_per_target),
      on: latest.latest_job_id == j.id,
      where: j.state in ^@unresolved_states,
      order_by: [desc: fragment("COALESCE(?, ?, ?)", j.discarded_at, j.attempted_at, j.inserted_at)],
      limit: ^limit,
      preload: [job: j, media_item: mi]
    )
    |> Repo.all()
  end

  @doc """
  How many jobs for this source are currently in flight (available, scheduled,
  executing, or retryable), counting both the source's own tasks and its media
  items' download tasks.

  Returns integer()
  """
  def count_in_flight_activity_for_source(%Source{} = source) do
    source
    |> activity_query()
    |> exclude(:preload)
    |> exclude(:select)
    |> where([t, j], j.state in ^@in_flight_states)
    |> Repo.aggregate(:count)
  end

  # The source's tasks, both direct and via its media items, with the job preloaded.
  #
  # The two sides are UNIONed rather than OR'd in a single WHERE: an
  # `t.source_id == ? OR media_items.source_id == ?` disjunction stops SQLite from
  # using either `tasks_source_id_index` or `media_items_source_id_index` and
  # degrades into a full scan of `tasks` (plus a temp b-tree for the ORDER BY),
  # which the LIMIT can't help with because the scan and sort happen first. With
  # the union, SQLite covers both branches with `tasks_source_id_index` /
  # `media_items_source_id_index` + `tasks_media_item_id_index` and looks the
  # tasks up by rowid.
  defp activity_query(%Source{} = source) do
    task_ids =
      from(t in Task, where: t.source_id == ^source.id, select: t.id)
      |> union_all(
        ^from(t in Task,
          join: mi in MediaItem,
          on: mi.id == t.media_item_id,
          where: mi.source_id == ^source.id,
          select: t.id
        )
      )

    from t in Task,
      join: j in assoc(t, :job),
      left_join: mi in MediaItem,
      on: mi.id == t.media_item_id,
      where: t.id in subquery(task_ids),
      preload: [job: j, media_item: mi]
  end

  @doc """
  Gets a single task.

  Returns %Task{}. Raises `Ecto.NoResultsError` if the Task does not exist.
  """
  def get_task!(id), do: Repo.get!(Task, id)

  @doc """
  Creates a task.

  Accepts map() | %Oban.Job{}, %Source{} | %Oban.Job{}, %MediaItem{}.
  Returns {:ok, %Task{}} | {:error, %Ecto.Changeset{}}.
  """
  def create_task(attrs) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
  end

  # This function's signature is designed to help simplify
  # usage of `create_job_with_task/2`
  def create_task(%Oban.Job{} = job, attached_record) do
    attached_record_attr =
      case attached_record do
        %Source{} = source -> %{source_id: source.id}
        %MediaItem{} = media_item -> %{media_item_id: media_item.id}
      end

    %Task{}
    |> Task.changeset(Map.merge(%{job_id: job.id}, attached_record_attr))
    |> Repo.insert()
  end

  @doc """
  Creates a job from given attrs, creating a task with an attached record
  if successful. Returns an error if the job already exists.

  Returns {:ok, %Task{}} | {:error, :duplicate_job} | {:error, %Ecto.Changeset{}}.
  """
  def create_job_with_task(job_attrs, task_attached_record) do
    case Repo.insert_unique_job(job_attrs) do
      {:ok, job} -> create_task(job, task_attached_record)
      {:duplicate, _} -> {:error, :duplicate_job}
      err -> err
    end
  end

  @doc """
  Deletes a task. Also cancels any attached job.

  Returns {:ok, %Task{}} | {:error, %Ecto.Changeset{}}.
  """
  def delete_task(%Task{} = task) do
    :ok = Oban.cancel_job(task.job_id)

    Repo.delete(task)
  end

  @doc """
  Deletes all tasks attached to a given record, cancelling any attached jobs.
  Optionally allows you to specify which worker and job states to include.

  Returns :ok
  """
  def delete_tasks_for(record, worker_name \\ nil, job_states \\ Oban.Job.states()) do
    record
    |> list_tasks_for(worker_name, job_states)
    |> Enum.each(&delete_task/1)
  end

  @doc """
  Deletes all _pending_ tasks attached to a given record, cancelling any attached jobs.
  Optionally allows you to specify which worker to include.

  Returns :ok
  """
  def delete_pending_tasks_for(record, worker_name \\ nil, opts \\ []) do
    include_executing = Keyword.get(opts, :include_executing, false)
    base_job_states = [:available, :scheduled, :retryable]
    job_states = if include_executing, do: base_job_states ++ [:executing], else: base_job_states

    delete_tasks_for(record, worker_name, job_states)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking task changes.
  """
  def change_task(%Task{} = task, attrs \\ %{}) do
    Task.changeset(task, attrs)
  end
end
