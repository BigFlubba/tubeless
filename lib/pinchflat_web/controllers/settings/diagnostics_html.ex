defmodule PinchflatWeb.Settings.DiagnosticsHTML do
  use PinchflatWeb, :html

  alias Pinchflat.Diagnostics.QueueDiagnostics
  alias Pinchflat.Diagnostics.DatabaseDiagnostics

  embed_templates "diagnostics_html/*"

  def retryable_jobs do
    QueueDiagnostics.get_retryable_jobs(20)
  end

  def discarded_jobs do
    QueueDiagnostics.get_discarded_jobs(20)
  end

  def stuck_jobs do
    QueueDiagnostics.get_stuck_jobs(30)
  end

  @queue_job_limit 50

  def queue_job_limit, do: @queue_job_limit

  def job_state_class("executing"), do: "text-green-400"
  def job_state_class("available"), do: "text-blue-400"
  def job_state_class("retryable"), do: "text-red-400"
  def job_state_class(_), do: "text-bodydark"

  attr :worker, :string, required: true
  attr :args, :map, required: true

  @doc """
  Renders what a job is acting on (a Source/MediaItem/MediaProfile), linking to
  the record when it still exists.
  """
  def job_details(assigns) do
    assigns = assign(assigns, :target, QueueDiagnostics.describe_job(assigns.worker, assigns.args))

    ~H"""
    <%= case @target do %>
      <% nil -> %>
        <span class="text-bodydark">-</span>
      <% %{type: :source, id: id, name: name} -> %>
        <.job_details_link href={~p"/sources/#{id}/#tab-tasks"} label={name} fallback={"Source ##{id}"} />
      <% %{type: :media_item, id: id, source_id: source_id, name: name} when not is_nil(source_id) -> %>
        <.job_details_link href={~p"/sources/#{source_id}/media/#{id}"} label={name} fallback={"Media ##{id}"} />
      <% %{type: :media_item, id: id, name: name} -> %>
        <span class="text-bodydark" title="The media item no longer exists">{name || "Media ##{id} (deleted)"}</span>
      <% %{type: :media_profile, id: id, name: name} -> %>
        <.job_details_link href={~p"/media_profiles/#{id}"} label={name} fallback={"Profile ##{id}"} />
    <% end %>
    """
  end

  attr :href, :string, required: true
  attr :label, :string, default: nil
  attr :fallback, :string, required: true

  defp job_details_link(assigns) do
    ~H"""
    <.link href={@href} class="text-primary hover:underline">{@label || @fallback}</.link>
    """
  end

  def system_stats do
    QueueDiagnostics.get_system_stats()
  end

  def database_stats do
    DatabaseDiagnostics.get_database_stats()
  end

  def table_row_counts do
    DatabaseDiagnostics.table_row_counts()
  end

  def orphaned_task_count do
    DatabaseDiagnostics.orphaned_task_count()
  end

  def latest_maintenance_job do
    DatabaseDiagnostics.latest_maintenance_job()
  end

  def scheduled_compaction_enabled? do
    Settings.get!(:database_maintenance_enabled)
  end

  def format_bytes(bytes) do
    DatabaseDiagnostics.format_bytes(bytes)
  end

  def format_table_name(table) do
    table
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  attr :job, :any, required: true

  @doc """
  Renders the outcome of the most recent database maintenance run (manual or
  scheduled), so successful and failed runs are both visible without digging
  through job records.
  """
  def maintenance_status(assigns) do
    ~H"""
    <%= case @job do %>
      <% nil -> %>
        <span class="text-bodydark">
          Never run. Compaction runs monthly on a schedule, or on demand via the Compact Now button.
        </span>
      <% %{state: "completed"} = job -> %>
        <span class="text-green-400">
          Succeeded at {format_datetime(job.completed_at)}, reclaimed {format_bytes(job.meta["reclaimed_bytes"] || 0)}.
        </span>
      <% %{state: state} = job when state in ["retryable", "discarded"] -> %>
        <span class="text-red-400">
          Failed at {format_datetime(job.attempted_at)}: {extract_last_error(job.errors)}
        </span>
        <span class="text-bodydark">
          {if state == "retryable",
            do: "It will be retried automatically — see Failed Jobs below.",
            else: "It has exhausted its retries — see the Discarded tab under Failed Jobs below."}
        </span>
      <% %{state: "executing"} = job -> %>
        <span class="text-blue-400">
          In progress since {format_datetime(job.attempted_at)} — waiting for running jobs to finish, then compacting.
        </span>
      <% %{state: "cancelled"} = job -> %>
        <span class="text-bodydark">
          Skipped at {format_datetime(job.cancelled_at)} — {extract_last_error(job.errors)}
        </span>
      <% job -> %>
        <span class="text-bodydark">Queued, will run at {format_datetime(job.scheduled_at)}.</span>
    <% end %>
    """
  end

  def diagnostic_info_string do
    """
    - App Version: #{Application.spec(:pinchflat)[:vsn]}
    - yt-dlp Version: #{Settings.get!(:yt_dlp_version)}
    - yt-dlp Update Behavior: #{Pinchflat.YtDlp.UpdateManager.humanize_policy(Settings.get!(:yt_dlp_update_policy))}
    - Apprise Version: #{Settings.get!(:apprise_version)}
    - System Architecture: #{to_string(:erlang.system_info(:system_architecture))}
    - Timezone: #{Application.get_env(:pinchflat, :timezone)}
    """
  end

  def format_worker_name(worker) do
    worker
    |> String.split(".")
    |> Enum.at(-1)
    |> format_worker_short_name()
  end

  defp format_worker_short_name("FastIndexingWorker"), do: "Fast Indexing"
  defp format_worker_short_name("MediaDownloadWorker"), do: "Download"
  defp format_worker_short_name("MediaCollectionIndexingWorker"), do: "Indexing"
  defp format_worker_short_name("MediaQualityUpgradeWorker"), do: "Quality Upgrade"
  defp format_worker_short_name("SourceMetadataStorageWorker"), do: "Metadata"
  defp format_worker_short_name(other), do: other

  def format_queue_name(queue) do
    queue
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  def format_datetime(nil), do: "-"

  def format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
  end

  def extract_last_error(errors) when is_list(errors) and errors != [] do
    errors
    |> List.last()
    |> Map.get("error", "Unknown error")
    |> String.slice(0, 200)
  end

  def extract_last_error(_), do: "No error details"

  def queue_health_class(stats) do
    cond do
      stats.paused -> "bg-yellow-500/20 border-yellow-500"
      stats.retryable > 0 -> "bg-red-500/20 border-red-500"
      stats.running >= stats.limit and stats.available > 0 -> "bg-blue-500/20 border-blue-500"
      true -> "bg-green-500/20 border-green-500"
    end
  end

  def queue_status_text(stats) do
    cond do
      stats.paused -> "Paused"
      stats.retryable > 0 -> "Has Failures"
      stats.running >= stats.limit -> "At Capacity"
      stats.running > 0 -> "Active"
      true -> "Idle"
    end
  end
end
