defmodule PinchflatWeb.Sources.SourceHTMLTest do
  use Pinchflat.DataCase

  alias PinchflatWeb.Sources.SourceHTML

  # `next_check_at/1` only reads each task's job worker and scheduled_at, so a
  # bare map stands in for the loaded task
  defp task(worker, scheduled_at) do
    %{job: %{worker: worker, scheduled_at: scheduled_at}}
  end

  defp in_hours(hours), do: DateTime.add(DateTime.utc_now(), hours, :hour)

  describe "next_check_at/1" do
    test "returns the soonest scheduled indexing run" do
      soon = in_hours(1)

      tasks = [
        task("Pinchflat.SlowIndexing.MediaCollectionIndexingWorker", in_hours(6)),
        task("Pinchflat.FastIndexing.FastIndexingWorker", soon)
      ]

      assert SourceHTML.next_check_at(tasks) == soon
    end

    test "ignores tasks that aren't indexing runs" do
      later = in_hours(6)

      tasks = [
        task("Pinchflat.Downloading.MediaDownloadWorker", in_hours(1)),
        task("Pinchflat.SlowIndexing.MediaCollectionIndexingWorker", later)
      ]

      assert SourceHTML.next_check_at(tasks) == later
    end

    test "returns nil when nothing is scheduled" do
      assert SourceHTML.next_check_at([]) == nil
      assert SourceHTML.next_check_at([task("Pinchflat.Downloading.MediaDownloadWorker", in_hours(1))]) == nil
    end

    test "returns nil when an indexing task has no scheduled_at" do
      assert SourceHTML.next_check_at([task("Pinchflat.FastIndexing.FastIndexingWorker", nil)]) == nil
    end

    # An executing job's scheduled_at is by definition in the past, and an overdue
    # available one can be too - neither should render as "Next check: 2 hours ago"
    test "returns :now when the soonest run is already due" do
      tasks = [
        task("Pinchflat.SlowIndexing.MediaCollectionIndexingWorker", in_hours(-2)),
        task("Pinchflat.FastIndexing.FastIndexingWorker", in_hours(1))
      ]

      assert SourceHTML.next_check_at(tasks) == :now
    end
  end
end
