defmodule Pinchflat.DatabaseTelemetry do
  @moduledoc false

  use GenServer

  require Logger

  @handler_id "pinchflat-database-telemetry"
  @repo_query_event [:pinchflat, :repo, :query]
  @pool_event [:pinchflat, :database, :pool]
  @slow_operation_event [:pinchflat, :database, :query, :slow]
  @transaction_event [:pinchflat, :database, :transaction, :stop]
  @transaction_started_key {__MODULE__, :transaction_started}
  @slow_operation_ms 1_000
  @slow_operation_native System.convert_time_unit(@slow_operation_ms, :millisecond, :native)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(nil) do
    :ok =
      :telemetry.attach(
        @handler_id,
        @repo_query_event,
        &__MODULE__.handle_repo_query/4,
        nil
      )

    {:ok, nil}
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach(@handler_id)
  end

  @doc false
  def handle_repo_query(_event, measurements, metadata, _config) do
    if slow_operation?(measurements) do
      :telemetry.execute(
        @slow_operation_event,
        %{count: 1, duration: measurements.total_time},
        metadata
      )
    end

    track_transaction(metadata)
  end

  @doc false
  def execute_pool_metrics do
    %{pid: pool, opts: opts} = Ecto.Adapter.lookup_meta(Pinchflat.Repo.get_dynamic_repo())
    pool_module = Keyword.get(opts, :pool, DBConnection.ConnectionPool)

    measurements =
      pool
      |> DBConnection.get_connection_metrics(pool: pool_module)
      |> Enum.reduce(
        %{ready_conn_count: 0, checkout_queue_length: 0},
        fn metric, totals ->
          %{
            ready_conn_count: totals.ready_conn_count + metric.ready_conn_count,
            checkout_queue_length: totals.checkout_queue_length + metric.checkout_queue_length
          }
        end
      )
      |> Map.put(:wal_size_bytes, wal_size_bytes())

    :telemetry.execute(@pool_event, measurements, %{repo: Pinchflat.Repo})
  rescue
    error ->
      # Never crash the poller (eg: Repo not started yet during boot), but log so a
      # permanent API/pool mismatch doesn't leave the gauges silently empty forever
      Logger.debug("DatabaseTelemetry pool metrics unavailable: #{inspect(error)}")
      :ok
  catch
    :exit, reason ->
      Logger.debug("DatabaseTelemetry pool metrics exited: #{inspect(reason)}")
      :ok
  end

  @doc false
  def query_error?(%{result: {:ok, _result}}), do: false
  def query_error?(%{result: _result}), do: true
  def query_error?(_metadata), do: false

  @doc false
  def slow_operation?(measurements) do
    Map.get(measurements, :total_time, 0) >= @slow_operation_native
  end

  @doc false
  def query_tag_values(metadata) do
    %{
      repo: normalize_module(Map.get(metadata, :repo, Pinchflat.Repo)),
      source: normalize_source(Map.get(metadata, :source)),
      command: query_command(Map.get(metadata, :query)),
      error: query_error_class(Map.get(metadata, :result))
    }
  end

  @doc false
  def connection_error_tag_values(%{error: error}) do
    %{
      repo: normalize_module(Pinchflat.Repo),
      reason: connection_error_reason(error)
    }
  end

  @doc false
  def connection_tag_values(metadata) do
    %{repo: normalize_module(Map.get(metadata, :tag, Pinchflat.Repo))}
  end

  @doc false
  def oban_exception_tag_values(metadata) do
    # `:telemetry.span` (which Oban's plugins use) reports the failure under
    # `:reason`, not `:error` — reading `:error` would tag every Stager crash
    # "unknown" and lose the busy/locked classification this metric exists for.
    %{
      plugin: normalize_module(Map.get(metadata, :plugin)),
      error: error_name(Map.get(metadata, :reason))
    }
  end

  @doc false
  def transaction_tag_values(metadata) do
    %{
      repo: normalize_module(Map.get(metadata, :repo, Pinchflat.Repo)),
      outcome: Map.get(metadata, :outcome, "unknown")
    }
  end

  defp wal_size_bytes do
    database = Pinchflat.Repo.config()[:database]

    case database && File.stat(database <> "-wal") do
      {:ok, %{size: size}} -> size
      _other -> 0
    end
  end

  defp track_transaction(metadata) do
    query = Map.get(metadata, :query)

    # Runs on every query in the client process, so the common case must be cheap.
    # Only begin/commit/rollback matter here; skip the command parse for anything
    # that can't start one (SELECT/INSERT/UPDATE/DELETE/… are the overwhelming bulk).
    if transaction_boundary_candidate?(query) do
      case {query_command(query), query_error?(metadata)} do
        {"begin", false} ->
          Process.put(@transaction_started_key, System.monotonic_time())

        {outcome, failed?} when outcome in ["commit", "rollback"] ->
          emit_transaction_duration(outcome, failed?, metadata)

        _other ->
          :ok
      end
    end
  end

  # begin / commit / rollback (any case), tolerating leading whitespace
  defp transaction_boundary_candidate?(query) when is_binary(query) do
    case query do
      <<c, _rest::binary>> when c in ~c"bBcCrR" -> true
      <<c, _rest::binary>> when c in ~c" \t\n\r" -> transaction_boundary_candidate?(String.trim_leading(query))
      _other -> false
    end
  end

  defp transaction_boundary_candidate?(_query), do: false

  defp emit_transaction_duration(outcome, failed?, metadata) do
    case Process.delete(@transaction_started_key) do
      started when is_integer(started) ->
        outcome = if failed?, do: outcome <> "_error", else: outcome

        :telemetry.execute(
          @transaction_event,
          %{duration: System.monotonic_time() - started},
          Map.put(metadata, :outcome, outcome)
        )

      _missing ->
        :ok
    end
  end

  defp query_error_class({:error, %Exqlite.Error{message: message}}),
    do: classify_message(message)

  defp query_error_class({:error, %DBConnection.ConnectionError{reason: reason}}),
    do: to_string(reason)

  defp query_error_class({:error, error}), do: error_name(error)
  defp query_error_class(_result), do: "none"

  defp classify_message(message) do
    message = String.downcase(message || "")

    cond do
      String.contains?(message, "database busy") -> "busy"
      String.contains?(message, "database is locked") -> "locked"
      String.contains?(message, "connection_closed") -> "connection_closed"
      String.contains?(message, "interrupted") -> "interrupted"
      String.contains?(message, "invoked incorrectly") -> "misuse"
      true -> "other"
    end
  end

  defp connection_error_reason(%DBConnection.ConnectionError{reason: reason}), do: to_string(reason)
  defp connection_error_reason(error), do: error_name(error)

  defp error_name(%module{}), do: normalize_module(module)
  defp error_name(error) when is_atom(error), do: Atom.to_string(error)
  defp error_name(_error), do: "unknown"

  defp query_command(query) when is_binary(query) do
    query
    |> String.trim_leading()
    |> String.split(~r/\s+/, parts: 2)
    |> List.first()
    |> case do
      nil -> "unknown"
      command -> String.downcase(command)
    end
  end

  defp query_command(_query), do: "unknown"

  defp normalize_source(nil), do: "source_unavailable"
  defp normalize_source(source) when is_atom(source), do: Atom.to_string(source)
  defp normalize_source(source) when is_binary(source), do: source
  defp normalize_source(_source), do: "source_unavailable"

  defp normalize_module(nil), do: "unknown"

  defp normalize_module(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.trim_leading("Elixir.")
  end

  defp normalize_module(_module), do: "unknown"
end
