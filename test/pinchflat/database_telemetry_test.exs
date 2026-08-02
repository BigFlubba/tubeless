defmodule Pinchflat.DatabaseTelemetryTest do
  use ExUnit.Case, async: false

  alias Pinchflat.DatabaseTelemetry
  alias Pinchflat.PromEx.Plugins.Database

  describe "query telemetry classification" do
    test "classifies SQLite busy errors without exposing query parameters" do
      metadata = %{
        repo: Pinchflat.Repo,
        source: "oban_jobs",
        query: "UPDATE oban_jobs SET state = ? WHERE id = ?",
        result: {:error, %Exqlite.Error{message: "Database busy"}}
      }

      assert DatabaseTelemetry.query_error?(metadata)

      assert DatabaseTelemetry.query_tag_values(metadata) == %{
               repo: "Pinchflat.Repo",
               source: "oban_jobs",
               command: "update",
               error: "busy"
             }
    end

    test "does not classify successful queries as errors" do
      metadata = %{result: {:ok, %{command: :select}}}

      refute DatabaseTelemetry.query_error?(metadata)
    end

    test "classifies slow operations at one second" do
      just_under = System.convert_time_unit(999, :millisecond, :native)
      threshold = System.convert_time_unit(1_000, :millisecond, :native)

      refute DatabaseTelemetry.slow_operation?(%{total_time: just_under})
      assert DatabaseTelemetry.slow_operation?(%{total_time: threshold})
    end

    test "emits a dedicated event only for slow operations" do
      handler_id = "slow-database-telemetry-test-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach(
          handler_id,
          [:pinchflat, :database, :query, :slow],
          fn event, measurements, metadata, test_pid ->
            send(test_pid, {event, measurements, metadata})
          end,
          self()
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      metadata = %{query: "SELECT 1", result: {:ok, %{command: :select}}}
      fast = %{total_time: System.convert_time_unit(999, :millisecond, :native)}
      slow = %{total_time: System.convert_time_unit(1_000, :millisecond, :native)}

      DatabaseTelemetry.handle_repo_query(nil, fast, metadata, nil)
      refute_receive {[:pinchflat, :database, :query, :slow], _, _}

      DatabaseTelemetry.handle_repo_query(nil, slow, metadata, nil)

      assert_receive {[:pinchflat, :database, :query, :slow], %{count: 1}, ^metadata}
    end

    test "measures the outer transaction from successful begin through commit" do
      handler_id = "transaction-telemetry-test-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach(
          handler_id,
          [:pinchflat, :database, :transaction, :stop],
          fn event, measurements, metadata, test_pid ->
            send(test_pid, {event, measurements, metadata})
          end,
          self()
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      measurements = %{total_time: 0}
      success = {:ok, %{command: :transaction}}

      DatabaseTelemetry.handle_repo_query(nil, measurements, %{query: "begin immediate", result: success}, nil)
      DatabaseTelemetry.handle_repo_query(nil, measurements, %{query: "commit", result: success}, nil)

      assert_receive {
        [:pinchflat, :database, :transaction, :stop],
        %{duration: duration},
        %{outcome: "commit"}
      }

      assert is_integer(duration)
      assert duration >= 0
    end

    test "tracks a transaction whose begin statement has leading whitespace" do
      handler_id = "transaction-ws-telemetry-test-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach(
          handler_id,
          [:pinchflat, :database, :transaction, :stop],
          fn event, measurements, metadata, test_pid ->
            send(test_pid, {event, measurements, metadata})
          end,
          self()
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      measurements = %{total_time: 0}
      success = {:ok, %{command: :transaction}}

      DatabaseTelemetry.handle_repo_query(nil, measurements, %{query: "  begin immediate", result: success}, nil)
      DatabaseTelemetry.handle_repo_query(nil, measurements, %{query: "commit", result: success}, nil)

      assert_receive {[:pinchflat, :database, :transaction, :stop], _measurements, %{outcome: "commit"}}
    end
  end

  describe "connection and Oban telemetry classification" do
    test "uses bounded connection-error reasons" do
      error = DBConnection.ConnectionError.exception("pool exhausted", :queue_timeout)

      assert DatabaseTelemetry.connection_error_tag_values(%{error: error}) == %{
               repo: "Pinchflat.Repo",
               reason: "queue_timeout"
             }
    end

    test "classifies Oban plugin exceptions from the :reason key that :telemetry.span reports" do
      metadata = %{plugin: Oban.Stager, kind: :error, reason: %Exqlite.Error{message: "Database busy"}}

      assert DatabaseTelemetry.oban_exception_tag_values(metadata) == %{
               plugin: "Oban.Stager",
               error: "Exqlite.Error"
             }
    end
  end

  test "publishes current pool and WAL measurements" do
    handler_id = "database-telemetry-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:pinchflat, :database, :pool],
        fn event, measurements, metadata, test_pid ->
          send(test_pid, {event, measurements, metadata})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert :ok = DatabaseTelemetry.execute_pool_metrics()

    assert_receive {[:pinchflat, :database, :pool], measurements, %{repo: Pinchflat.Repo}}
    assert is_integer(measurements.ready_conn_count)
    assert measurements.ready_conn_count >= 0
    assert is_integer(measurements.checkout_queue_length)
    assert measurements.checkout_queue_length >= 0
    assert is_integer(measurements.wal_size_bytes)
    assert measurements.wal_size_bytes >= 0
  end

  test "defines event and polling metric groups" do
    assert %{metrics: event_metrics} = Database.event_metrics(otp_app: :pinchflat)
    assert %{metrics: polling_metrics} = Database.polling_metrics(otp_app: :pinchflat)

    assert length(event_metrics) == 7
    assert length(polling_metrics) == 3
  end
end
