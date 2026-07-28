defmodule Pinchflat.Diagnostics.SystemStatusTest do
  use Pinchflat.DataCase

  alias Pinchflat.Diagnostics.SystemStatus
  alias Pinchflat.Media
  alias Pinchflat.Repo
  alias Pinchflat.Sources.Source

  import Pinchflat.ProfilesFixtures

  setup do
    stub(DiskSpaceCheckerMock, :space_info, fn _path ->
      {:ok,
       %{
         available_bytes: 10 * 1024 * 1024 * 1024,
         total_bytes: 40 * 1024 * 1024 * 1024,
         used_percent: 75,
         mountpoint: "/"
       }}
    end)

    :ok
  end

  test "summarizes the home-page entities without inspecting media files" do
    profile = media_profile_fixture()
    enabled_source = source_fixture(profile.id, true)
    _disabled_source = source_fixture(profile.id, false)

    {:ok, _media} =
      Media.create_media_item(%{
        media_id: "system-status-media",
        title: "System status media",
        original_url: "https://example.com/watch?v=system-status-media",
        livestream: false,
        short_form_content: false,
        source_id: enabled_source.id,
        uploaded_at: DateTime.utc_now(),
        media_filepath: "/video/system-status-media.mp4",
        media_size_bytes: 2048
      })

    status = SystemStatus.get()

    assert status.sources == %{total: 2, enabled: 1, profile_count: 1}
    assert status.library == %{downloaded: 1, size_bytes: 2048}
    assert status.failed_recently == 0
    assert status.failure_window_hours == 24
    assert status.database.size_bytes >= 0
    assert is_integer(status.database.reclaimable_bytes)
    assert is_integer(status.database.wal_bytes)
    assert status.queues.queue_count > 0
  end

  test "reports storage stats with a denominator and marks collocated volumes" do
    status = SystemStatus.get()

    assert status.storage.media.available_bytes == 10 * 1024 * 1024 * 1024
    assert status.storage.media.total_bytes == 40 * 1024 * 1024 * 1024
    assert status.storage.media.used_percent == 75
    assert status.storage.database.available_bytes == 10 * 1024 * 1024 * 1024
    # Both directories resolve to the same mount point in the stub, so they're collocated
    assert status.storage.collocated == true
  end

  test "treats separate mount points as non-collocated" do
    media_dir = Application.fetch_env!(:pinchflat, :media_directory)

    stub(DiskSpaceCheckerMock, :space_info, fn
      ^media_dir ->
        {:ok, %{available_bytes: 100, total_bytes: 200, used_percent: 50, mountpoint: "/mnt/media"}}

      _path ->
        {:ok, %{available_bytes: 100, total_bytes: 200, used_percent: 50, mountpoint: "/"}}
    end)

    status = SystemStatus.get()

    assert status.storage.media.mountpoint == "/mnt/media"
    assert status.storage.database.mountpoint == "/"
    assert status.storage.collocated == false
  end

  test "reports missing storage info without crashing" do
    stub(DiskSpaceCheckerMock, :space_info, fn _path -> :error end)

    status = SystemStatus.get()

    assert status.storage.media.available_bytes == nil
    assert status.storage.collocated == false
  end

  defp source_fixture(media_profile_id, enabled) do
    suffix = System.unique_integer([:positive])

    %Source{}
    |> Source.changeset(
      %{
        enabled: enabled,
        collection_name: "System Status Source #{suffix}",
        collection_id: "system-status-source-#{suffix}",
        collection_type: :channel,
        custom_name: "System Status Source #{suffix}",
        description: "",
        original_url: "https://example.com/system-status-source-#{suffix}",
        media_profile_id: media_profile_id,
        index_frequency_minutes: 60,
        fast_index: false,
        download_media: true,
        slug: "system-status-source-#{suffix}"
      },
      :pre_insert
    )
    |> Repo.insert!()
  end
end
