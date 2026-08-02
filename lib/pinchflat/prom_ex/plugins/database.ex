defmodule Pinchflat.PromEx.Plugins.Database do
  @moduledoc false

  use PromEx.Plugin

  alias Pinchflat.DatabaseTelemetry

  @repo_query_event [:pinchflat, :repo, :query]
  @slow_operation_event [:pinchflat, :database, :query, :slow]
  @transaction_event [:pinchflat, :database, :transaction, :stop]
  @connection_error_event [:db_connection, :connection_error]
  @connection_connected_event [:db_connection, :connected]
  @connection_disconnected_event [:db_connection, :disconnected]
  @oban_plugin_exception_event [:oban, :plugin, :exception]
  @pool_event [:pinchflat, :database, :pool]

  @impl true
  def event_metrics(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    metric_prefix = Keyword.get(opts, :metric_prefix, PromEx.metric_prefix(otp_app, :database))

    Event.build(
      :pinchflat_database_event_metrics,
      [
        counter(metric_prefix ++ [:query, :errors, :total],
          event_name: @repo_query_event,
          description: "The number of failed database queries, classified by bounded error type.",
          measurement: fn _measurements -> 1 end,
          tags: [:repo, :source, :command, :error],
          tag_values: &DatabaseTelemetry.query_tag_values/1,
          drop: fn metadata -> not DatabaseTelemetry.query_error?(metadata) end
        ),
        counter(metric_prefix ++ [:query, :slow, :total],
          event_name: @slow_operation_event,
          description: "The number of database operations taking at least one second.",
          measurement: :count,
          tags: [:repo, :source, :command],
          tag_values: &DatabaseTelemetry.query_tag_values/1
        ),
        distribution(metric_prefix ++ [:transaction, :duration, :milliseconds],
          event_name: @transaction_event,
          description: "The time a process held an outer database transaction open.",
          measurement: :duration,
          reporter_options: [buckets: [10, 50, 100, 500, 1_000, 5_000, 15_000, 30_000]],
          unit: {:native, :millisecond},
          tags: [:repo, :outcome],
          tag_values: &DatabaseTelemetry.transaction_tag_values/1
        ),
        counter(metric_prefix ++ [:connection, :errors, :total],
          event_name: @connection_error_event,
          description: "The number of database connection checkout errors.",
          measurement: :count,
          tags: [:repo, :reason],
          tag_values: &DatabaseTelemetry.connection_error_tag_values/1
        ),
        counter(metric_prefix ++ [:connection, :connected, :total],
          event_name: @connection_connected_event,
          description: "The number of database connections established.",
          measurement: :count,
          tags: [:repo],
          tag_values: &DatabaseTelemetry.connection_tag_values/1
        ),
        counter(metric_prefix ++ [:connection, :disconnected, :total],
          event_name: @connection_disconnected_event,
          description: "The number of database connections disconnected.",
          measurement: :count,
          tags: [:repo],
          tag_values: &DatabaseTelemetry.connection_tag_values/1
        ),
        counter(metric_prefix ++ [:oban, :plugin, :exceptions, :total],
          event_name: @oban_plugin_exception_event,
          description: "The number of Oban plugin exceptions, including Stager failures.",
          measurement: fn _measurements -> 1 end,
          tags: [:plugin, :error],
          tag_values: &DatabaseTelemetry.oban_exception_tag_values/1
        )
      ]
    )
  end

  @impl true
  def polling_metrics(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    metric_prefix = Keyword.get(opts, :metric_prefix, PromEx.metric_prefix(otp_app, :database))
    poll_rate = Keyword.get(opts, :poll_rate, 5_000)

    Polling.build(
      :pinchflat_database_pool_polling_metrics,
      poll_rate,
      {DatabaseTelemetry, :execute_pool_metrics, []},
      [
        last_value(metric_prefix ++ [:pool, :ready, :connections],
          event_name: @pool_event,
          description: "The number of database connections immediately available.",
          measurement: :ready_conn_count,
          tags: [:repo],
          tag_values: &DatabaseTelemetry.connection_tag_values/1
        ),
        last_value(metric_prefix ++ [:pool, :checkout, :queue, :length],
          event_name: @pool_event,
          description: "The number of processes waiting to check out a database connection.",
          measurement: :checkout_queue_length,
          tags: [:repo],
          tag_values: &DatabaseTelemetry.connection_tag_values/1
        ),
        last_value(metric_prefix ++ [:sqlite, :wal, :size, :bytes],
          event_name: @pool_event,
          description: "The size of SQLite's WAL sidecar file in bytes.",
          measurement: :wal_size_bytes,
          tags: [:repo],
          tag_values: &DatabaseTelemetry.connection_tag_values/1
        )
      ],
      detach_on_error: false
    )
  end
end
