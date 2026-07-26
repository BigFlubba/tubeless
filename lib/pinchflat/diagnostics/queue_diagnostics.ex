defmodule Pinchflat.Diagnostics.QueueDiagnostics do
  @moduledoc """
  Provides diagnostic information about Oban job queues.
  """

  import Ecto.Query

  alias Pinchflat.Media.MediaItem
  alias Pinchflat.Media.MediaQuery
  alias Pinchflat.Profiles.MediaProfile
  alias Pinchflat.Repo
  alias Pinchflat.Sources.Source
  alias Pinchflat.Tasks

  # Worker (short) names grouped by the kind of record their "id" arg points at,
  # so a diagnostics row can show what a job is actually working on.
  @media_item_workers ~w(MediaDownloadWorker MediaQualityUpgradeWorker)
  @source_workers ~w(
    MediaCollectionIndexingWorker FastIndexingWorker
    SourceMetadataStorageWorker SourceDeletionWorker FileSyncingWorker
  )
  @media_profile_workers ~w(MediaProfileDeletionWorker)

  @doc """
  Returns a list of all queue names, derived from the Oban configuration so it
  can't silently drift from the queues that actually run.
  """
  def queue_names do
    case Application.get_env(:pinchflat, Oban, [])[:queues] do
      queues when is_list(queues) -> Keyword.keys(queues)
      _ -> []
    end
  end

  @doc """
  Returns health status for all queues including job counts by state.
  """
  def get_all_queue_stats do
    Enum.map(queue_names(), fn queue_name ->
      # check_queue returns nil when the queue's producer isn't running (e.g.
      # mid-startup) — fall back to zeros instead of crashing the page.
      queue_info = Oban.check_queue(queue: queue_name) || %{}
      job_counts = get_job_counts_for_queue(queue_name)

      %{
        name: queue_name,
        running: length(Map.get(queue_info, :running, [])),
        limit: Map.get(queue_info, :limit, 0),
        paused: Map.get(queue_info, :paused, false),
        available: Map.get(job_counts, :available, 0),
        scheduled: Map.get(job_counts, :scheduled, 0),
        retryable: Map.get(job_counts, :retryable, 0),
        executing: Map.get(job_counts, :executing, 0)
      }
    end)
  end

  @doc """
  Returns the jobs currently sitting in a queue (executing, available, scheduled
  or retryable), ordered so that what's running/runnable comes first. Capped by
  `limit` so a deep backlog can't blow up the diagnostics page.
  """
  def get_jobs_for_queue(queue_name, limit \\ 50) do
    queue_string = to_string(queue_name)

    from(j in Oban.Job,
      where: j.queue == ^queue_string,
      where: j.state in ["executing", "available", "scheduled", "retryable"],
      order_by: [
        asc:
          fragment(
            "CASE ? WHEN 'executing' THEN 0 WHEN 'available' THEN 1 WHEN 'retryable' THEN 2 ELSE 3 END",
            j.state
          ),
        asc: j.scheduled_at,
        asc: j.id
      ],
      limit: ^limit,
      select: %{
        id: j.id,
        worker: j.worker,
        state: j.state,
        attempt: j.attempt,
        max_attempts: j.max_attempts,
        args: j.args,
        scheduled_at: j.scheduled_at
      }
    )
    |> Repo.all()
  end

  @doc """
  Returns jobs that are in a retryable state (failed but will retry).
  """
  def get_retryable_jobs(limit \\ 50) do
    from(j in Oban.Job,
      where: j.state == "retryable",
      order_by: [desc: j.attempted_at],
      limit: ^limit,
      select: %{
        id: j.id,
        queue: j.queue,
        worker: j.worker,
        state: j.state,
        attempt: j.attempt,
        max_attempts: j.max_attempts,
        errors: j.errors,
        args: j.args,
        attempted_at: j.attempted_at,
        scheduled_at: j.scheduled_at
      }
    )
    |> Repo.all()
  end

  @doc """
  Returns jobs that have been discarded (failed and exhausted all retries).
  """
  def get_discarded_jobs(limit \\ 50) do
    from(j in Oban.Job,
      where: j.state == "discarded",
      order_by: [desc: j.discarded_at],
      limit: ^limit,
      select: %{
        id: j.id,
        queue: j.queue,
        worker: j.worker,
        state: j.state,
        attempt: j.attempt,
        max_attempts: j.max_attempts,
        errors: j.errors,
        args: j.args,
        discarded_at: j.discarded_at
      }
    )
    |> Repo.all()
  end

  @doc """
  Returns jobs that are pending against a Source that no longer exists — the
  "removed source" cruft that accumulates when a deletion cascade or a failed
  retry-transition leaves a job stranded pointing at a gone source (see the
  zombie `SourceDeletionWorker` jobs stuck `available` with retries exhausted).

  Deliberately scoped to source-keyed workers only (not media-download jobs,
  which can orphan in the hundreds when a source is deleted). This keeps the
  list short and individually actionable, which is the whole point — it's not a
  bulk queue rebuild. Terminal history (`completed`/`cancelled`) is excluded.
  """
  def get_orphaned_source_jobs(limit \\ 50) do
    orphaned_source_jobs_query()
    |> order_by([j], asc: j.id)
    |> limit(^limit)
    |> select([j], %{
      id: j.id,
      queue: j.queue,
      worker: j.worker,
      state: j.state,
      attempt: j.attempt,
      max_attempts: j.max_attempts,
      errors: j.errors,
      args: j.args,
      inserted_at: j.inserted_at
    })
    |> Repo.all()
  end

  @doc """
  Counts orphaned source jobs (see `get_orphaned_source_jobs/1`) for the tab badge.
  """
  def count_orphaned_source_jobs do
    orphaned_source_jobs_query()
    |> Repo.aggregate(:count)
  end

  @doc """
  Deletes a single orphaned source job by ID, but only after re-verifying it's
  genuinely orphaned (right worker, non-terminal state, source really gone) so a
  stale or crafted ID can't drop a job that's still meant to run. Deleting the
  `oban_jobs` row cascades its `tasks` row.
  """
  def delete_orphaned_source_job(job_id) do
    query = from(j in orphaned_source_jobs_query(), where: j.id == ^job_id)

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      job ->
        :ok = Oban.delete_job(job)
        {:ok, :deleted}
    end
  end

  @doc """
  Deletes every orphaned source job in one pass. Returns the count removed.
  """
  def delete_all_orphaned_source_jobs do
    {count, _} =
      from(j in orphaned_source_jobs_query())
      |> Repo.delete_all()

    count
  end

  @doc """
  Returns jobs that have exhausted their attempt budget (`attempt >= max_attempts`)
  yet are still in a runnable, non-terminal state — the class of "stalled" job that
  falls between the Retryable, Discarded and Orphaned checks.

  Oban's SQLite (Lite) engine only ever fetches `available` jobs where
  `attempt < max_attempts`, so a job that reaches its ceiling without going through
  the normal failure path is never picked up again — and, never running, is never
  discarded either. The canonical way in is a job that was `executing` during an
  ungraceful shutdown: boot recovery flips it `executing -> retryable` without
  recording an error or bumping the ceiling, the stager moves it to `available`, and
  it climbs to `attempt == max_attempts` across repeated shutdowns until it can never
  be fetched. For workers with `unique: [states: :incomplete]` (several cron workers,
  e.g. media retention) that stuck row also blocks every replacement from being
  enqueued, silently killing a recurring job for as long as it sits there.

  `executing` is deliberately excluded: a job legitimately on its final attempt sits
  at `attempt == max_attempts` while it runs, and it is not stuck.
  """
  def get_stalled_jobs(limit \\ 50) do
    stalled_jobs_query()
    |> order_by([j], asc: j.id)
    |> limit(^limit)
    |> select([j], %{
      id: j.id,
      queue: j.queue,
      worker: j.worker,
      state: j.state,
      attempt: j.attempt,
      max_attempts: j.max_attempts,
      args: j.args,
      attempted_at: j.attempted_at
    })
    |> Repo.all()
  end

  @doc """
  Counts stalled jobs (see `get_stalled_jobs/1`) for the tab badge.
  """
  def count_stalled_jobs do
    stalled_jobs_query()
    |> Repo.aggregate(:count)
  end

  @doc """
  Resets a single stalled job (see `get_stalled_jobs/1`) by handing it a fresh attempt
  budget so Oban will run it again: state -> `available`, `attempt` -> 0, errors
  cleared, `scheduled_at` -> now.

  Resetting (re-running) is the *only* remedy offered, and that's deliberate — it's the
  one action that's correct no matter what created the job:

    * A cron job runs and, on completion, leaves the `:incomplete` set so its schedule
      resumes. A self-perpetuating indexing job runs and schedules its successor,
      reviving the chain. A one-shot download job simply runs. Discarding would only be
      safe for jobs something *else* re-creates (cron, boot-time chain revival) and
      would silently drop one-shot work that nothing re-enqueues.
    * `attempt` is reset to 0, not 1, so the fix holds for *every* worker regardless of
      `max_attempts` — including `max_attempts: 1` workers such as `ReconcileWorker`,
      where an `attempt: 1` reset would still satisfy `attempt >= max_attempts` and
      leave the job exactly as stuck. A freshly inserted job starts at 0; this mirrors
      that.

  The update is scoped to the stalled predicate, so a stale id, or a job that changed
  state since the page rendered, matches nothing — a job that is legitimately running
  can't be reset out from under itself. Returns the number of rows reset (0 or 1).
  """
  def reset_stalled_job(job_id) do
    {count, _} =
      from(j in stalled_jobs_query(), where: j.id == ^job_id)
      |> Repo.update_all(set: stalled_reset_updates())

    count
  end

  @doc """
  Resets every stalled job in one pass (see `reset_stalled_job/1`). Returns the count.
  """
  def reset_all_stalled_jobs do
    {count, _} =
      stalled_jobs_query()
      |> Repo.update_all(set: stalled_reset_updates())

    count
  end

  defp stalled_reset_updates do
    [state: "available", attempt: 0, errors: [], scheduled_at: DateTime.utc_now()]
  end

  # Jobs that have hit their attempt ceiling but haven't reached a terminal state.
  # `executing` is excluded (a job on its final attempt runs at attempt == max and
  # isn't stuck); terminal states (`completed`/`cancelled`/`discarded`) are excluded
  # because those are resolved, not stalled.
  @stalled_states ~w(available scheduled retryable)

  defp stalled_jobs_query do
    from(j in Oban.Job,
      where: j.state in @stalled_states,
      where: j.attempt >= j.max_attempts
    )
  end

  # Source-keyed workers whose `args["id"]` points at a Source. A pending job here
  # is orphaned exactly when that Source is gone. A legitimately-queued
  # SourceDeletionWorker still has its Source (it deletes it when it runs), so it
  # won't match until the Source is actually gone.
  @orphanable_source_workers [
    "Pinchflat.SlowIndexing.MediaCollectionIndexingWorker",
    "Pinchflat.FastIndexing.FastIndexingWorker",
    "Pinchflat.Metadata.SourceMetadataStorageWorker",
    "Pinchflat.Sources.SourceDeletionWorker",
    "Pinchflat.Media.FileSyncingWorker"
  ]

  @orphan_source_states ~w(available scheduled retryable discarded)

  defp orphaned_source_jobs_query do
    from(j in Oban.Job,
      where: j.state in @orphan_source_states,
      where: j.worker in @orphanable_source_workers,
      where: not is_nil(fragment("json_extract(?, '$.id')", j.args)),
      where:
        fragment(
          "NOT EXISTS (SELECT 1 FROM sources s WHERE s.id = json_extract(?, '$.id'))",
          j.args
        )
    )
  end

  @doc """
  Resolves an Oban job's worker + args into a human-friendly description of the
  record it's acting on (a Source, MediaItem or MediaProfile).

  Returns a map with `:type`, `:id`, `:name` and (for media items) `:source_id`,
  or `nil` when the job has no resolvable target. `:name` is `nil` when the record
  has since been deleted, so callers can still show which id it referenced.
  """
  def describe_job(worker, args) do
    short_name = worker |> to_string() |> String.split(".") |> List.last()
    id = args["id"]

    cond do
      is_nil(id) -> nil
      short_name in @media_item_workers -> describe_media_item(id)
      short_name in @source_workers -> describe_source(id)
      short_name in @media_profile_workers -> describe_media_profile(id)
      true -> nil
    end
  end

  defp describe_media_item(id) do
    item =
      from(m in MediaItem, where: m.id == ^id, select: %{source_id: m.source_id, name: m.title})
      |> Repo.one()

    case item do
      nil -> %{type: :media_item, id: id, source_id: nil, name: nil}
      %{source_id: source_id, name: name} -> %{type: :media_item, id: id, source_id: source_id, name: name}
    end
  end

  defp describe_source(id) do
    name =
      from(s in Source, where: s.id == ^id, select: coalesce(s.custom_name, s.collection_name))
      |> Repo.one()

    %{type: :source, id: id, source_id: id, name: name}
  end

  defp describe_media_profile(id) do
    name = from(p in MediaProfile, where: p.id == ^id, select: p.name) |> Repo.one()

    %{type: :media_profile, id: id, name: name}
  end

  @doc """
  Returns jobs that appear to be stuck (executing for too long or orphaned).
  A job is considered stuck if it's been "executing" for more than the threshold.
  """
  def get_stuck_jobs(threshold_minutes \\ 30) do
    threshold = DateTime.add(DateTime.utc_now(), -threshold_minutes * 60, :second)

    from(j in Oban.Job,
      where: j.state == "executing",
      where: j.attempted_at < ^threshold,
      order_by: [asc: j.attempted_at],
      select: %{
        id: j.id,
        queue: j.queue,
        worker: j.worker,
        attempt: j.attempt,
        attempted_at: j.attempted_at,
        args: j.args
      }
    )
    |> Repo.all()
  end

  @doc """
  Resets all retryable jobs by clearing their error history and marking as available.
  Returns the number of jobs reset.
  """
  def reset_retryable_jobs do
    {count, _} =
      from(j in Oban.Job,
        where: j.state == "retryable"
      )
      |> Repo.update_all(set: [state: "available", attempt: 1, errors: [], scheduled_at: DateTime.utc_now()])

    count
  end

  @doc """
  Resets a specific job by ID.

  Only retryable or discarded jobs can be reset. Executing jobs are deliberately
  excluded: a job may be genuinely running, and flipping it back to available would
  let a producer start a second copy concurrently (double execution). Orphaned
  executing jobs are recovered at boot by `Pinchflat.Boot.PreJobStartupTasks`.
  """
  def reset_job(job_id) do
    {count, _} =
      from(j in Oban.Job,
        where: j.id == ^job_id,
        where: j.state in ["retryable", "discarded"]
      )
      |> Repo.update_all(set: [state: "available", attempt: 1, errors: [], scheduled_at: DateTime.utc_now()])

    count
  end

  @doc """
  Requeues a job by ID: cancels the current job (killing its running process if
  it's executing) and enqueues a fresh copy of the same worker + args at the back
  of the queue, so any other jobs already waiting get to run first.

  This is the safe replacement for a bare cancel. A plain cancel silently drops
  the work — which is especially painful for setups running a single worker
  (`YT_DLP_WORKER_CONCURRENCY=1`), where a long slow-index holds the only slot and
  the user just wants to yield it to other jobs without losing the index entirely.

  When the target resolves to a Source or MediaItem, the new job is created through
  `Tasks.create_job_with_task/2` so it keeps its Task linkage (and is therefore
  still cancelled by the deletion cascade). Other workers fall back to a plain
  insert. The requeued job is enqueued as `available`, so Oban's `priority`,
  `scheduled_at`, then `id` ordering naturally places it behind work already in the
  queue.

  Returns {:ok, :requeued} | {:error, term()}.
  """
  def requeue_job(job_id) do
    case Repo.get(Oban.Job, job_id) do
      nil -> {:error, :not_found}
      job -> requeue_existing_job(job)
    end
  end

  defp requeue_existing_job(job) do
    changeset = Module.safe_concat([job.worker]).new(job.args)

    :ok = Oban.cancel_job(job.id)

    result =
      case requeue_target(job) do
        %Source{} = record -> Tasks.create_job_with_task(changeset, record)
        %MediaItem{} = record -> Tasks.create_job_with_task(changeset, record)
        _ -> Oban.insert(changeset)
      end

    case result do
      # A duplicate means an equivalent job is already queued, which satisfies the
      # intent (the work will still run) — so treat it as a successful requeue.
      {:ok, _} -> {:ok, :requeued}
      {:error, :duplicate_job} -> {:ok, :requeued}
      {:error, reason} -> {:error, reason}
    end
  rescue
    ArgumentError -> {:error, :unknown_worker}
  end

  # Resolves the record a job targets so the requeued copy can be re-linked to a
  # Task. Mirrors the worker→record grouping used by `describe_job/2`.
  defp requeue_target(job) do
    short_name = job.worker |> String.split(".") |> List.last()
    id = job.args["id"]

    cond do
      is_nil(id) -> nil
      short_name in @media_item_workers -> Repo.get(MediaItem, id)
      short_name in @source_workers -> Repo.get(Source, id)
      true -> nil
    end
  end

  @doc """
  Permanently deletes a discarded job by ID so it stops showing up in diagnostics.

  Scoped to `discarded` jobs only: deleting an available/scheduled/retryable job
  would silently drop work that's still meant to run, and Oban won't delete an
  executing job anyway.
  """
  def delete_discarded_job(job_id) do
    case Repo.get_by(Oban.Job, id: job_id, state: "discarded") do
      nil ->
        {:error, :not_found}

      job ->
        :ok = Oban.delete_job(job)
        {:ok, :deleted}
    end
  end

  @doc """
  Returns summary statistics for the system.
  """
  def get_system_stats do
    %{
      total_pending_downloads: count_pending_downloads(),
      total_downloaded: count_downloaded_media(),
      library_size_bytes: sum_library_size_bytes(),
      total_media_items: count_media_items(),
      total_sources: count_sources()
    }
  end

  # Private functions

  defp get_job_counts_for_queue(queue_name) do
    queue_string = Atom.to_string(queue_name)

    from(j in Oban.Job,
      where: j.queue == ^queue_string,
      where: j.state in ["available", "scheduled", "retryable", "executing"],
      group_by: j.state,
      select: {j.state, count(j.id)}
    )
    |> Repo.all()
    |> Enum.into(%{}, fn {state, count} -> {String.to_atom(state), count} end)
  end

  defp count_pending_downloads do
    # Reuse the canonical pending definition so this matches what the app actually
    # schedules for download (accounts for source cutoff, shorts/livestream rules,
    # title regex and duration limits) rather than every un-downloaded item.
    MediaQuery.new()
    |> MediaQuery.require_assoc(:media_profile)
    |> where(^MediaQuery.pending())
    |> Repo.aggregate(:count)
  end

  defp count_downloaded_media do
    from(m in Pinchflat.Media.MediaItem,
      where: not is_nil(m.media_filepath)
    )
    |> Repo.aggregate(:count)
  end

  defp sum_library_size_bytes do
    MediaQuery.new()
    |> where(^MediaQuery.downloaded())
    |> Repo.aggregate(:sum, :media_size_bytes) || 0
  end

  defp count_sources do
    Repo.aggregate(Pinchflat.Sources.Source, :count)
  end

  defp count_media_items do
    Repo.aggregate(Pinchflat.Media.MediaItem, :count)
  end
end
