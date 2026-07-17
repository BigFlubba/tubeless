defmodule Pinchflat.Settings.QueueHealthLive do
  @moduledoc """
  The Queue Health section of the diagnostics page. A LiveView so the Refresh
  button can re-fetch queue stats in place rather than reloading the whole page.
  """

  use PinchflatWeb, :live_view

  import PinchflatWeb.Settings.DiagnosticsHTML,
    only: [
      format_queue_name: 1,
      format_worker_name: 1,
      format_datetime: 1,
      queue_status_text: 1,
      queue_health_class: 1,
      queue_job_limit: 0,
      job_state_class: 1,
      job_details: 1
    ]

  alias Pinchflat.Diagnostics.QueueDiagnostics

  def render(assigns) do
    ~H"""
    <div class="rounded-sm border border-stroke bg-white px-5 py-5 shadow-default dark:border-strokedark dark:bg-boxdark sm:px-7.5 mb-6">
      <div class="flex justify-between items-center mb-4">
        <h3 class="text-lg font-semibold text-white">Queue Health</h3>
        <div class="flex items-center gap-3">
          <span class="text-xs text-bodydark">Updated {format_datetime(@last_refreshed_at)}</span>
          <.button color="bg-bodydark" rounding="rounded-lg" class="text-sm" phx-click="refresh">
            <.icon name="hero-arrow-path" class="h-4 w-4 mr-1" /> Refresh
          </.button>
        </div>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <%= for %{stats: stats, jobs: jobs} <- @queues do %>
          <div class={"rounded-lg border-2 p-4 #{queue_health_class(stats)}"} x-data="{ open: false }">
            <div class="flex justify-between items-start mb-2">
              <h4 class="font-semibold text-white">{format_queue_name(stats.name)}</h4>
              <span class={"text-xs px-2 py-1 rounded #{if stats.paused, do: "bg-yellow-500", else: "bg-meta-4"}"}>
                {queue_status_text(stats)}
              </span>
            </div>
            <div class="grid grid-cols-2 gap-2 text-sm">
              <div>
                <span class="text-bodydark">Running:</span>
                <span class="text-white ml-1">{stats.running}/{stats.limit}</span>
              </div>
              <div>
                <span class="text-bodydark">Available:</span>
                <span class="text-white ml-1">{stats.available}</span>
              </div>
              <div>
                <span class="text-bodydark">Scheduled:</span>
                <span class="text-white ml-1">{stats.scheduled}</span>
              </div>
              <div>
                <span class={"#{if stats.retryable > 0, do: "text-red-400", else: "text-bodydark"}"}>Retryable:</span>
                <span class={"ml-1 #{if stats.retryable > 0, do: "text-red-400 font-bold", else: "text-white"}"}>
                  {stats.retryable}
                </span>
              </div>
            </div>

            <%= if length(jobs) > 0 do %>
              <button
                type="button"
                x-on:click="open = !open"
                class="mt-3 flex items-center gap-1 text-xs text-bodydark hover:text-white"
              >
                <.icon name="hero-chevron-right" class="h-3 w-3 transition-transform" x-bind:class="open && 'rotate-90'" />
                <span x-text="open ? 'Hide queue' : 'View queue'"></span>
                <span>({length(jobs)}{if length(jobs) >= queue_job_limit(), do: "+"})</span>
              </button>
              <div x-cloak x-show="open" x-transition class="mt-2">
                <div class="max-h-64 overflow-y-auto rounded border border-strokedark/50 bg-black/20">
                  <table class="w-full text-xs">
                    <tbody>
                      <%= for job <- jobs do %>
                        <tr class="border-b border-strokedark/30 last:border-0">
                          <td class="py-1 px-2 text-bodydark whitespace-nowrap">#{job.id}</td>
                          <td class="py-1 px-2 text-white">{format_worker_name(job.worker)}</td>
                          <td class="py-1 px-2 whitespace-nowrap">
                            <.job_details worker={job.worker} args={job.args} />
                          </td>
                          <td class={"py-1 px-2 whitespace-nowrap #{job_state_class(job.state)}"}>{job.state}</td>
                          <td class="py-1 px-2 text-bodydark whitespace-nowrap">{format_datetime(job.scheduled_at)}</td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
                <%= if length(jobs) >= queue_job_limit() do %>
                  <p class="text-xs text-bodydark mt-1">Showing first {queue_job_limit()} jobs.</p>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, refresh_queue_data(socket)}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, refresh_queue_data(socket)}
  end

  defp refresh_queue_data(socket) do
    queues =
      Enum.map(QueueDiagnostics.get_all_queue_stats(), fn stats ->
        %{stats: stats, jobs: QueueDiagnostics.get_jobs_for_queue(stats.name, queue_job_limit())}
      end)

    assign(socket, queues: queues, last_refreshed_at: DateTime.utc_now())
  end
end
