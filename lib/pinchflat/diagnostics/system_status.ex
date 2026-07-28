defmodule Pinchflat.Diagnostics.SystemStatus do
  @moduledoc """
  Collects the small, inexpensive system summary shown on the home page.

  Everything here is counts, grouped queries, cheap SQLite PRAGMAs, and
  filesystem metadata (`df`). It never walks the media directory, invokes
  yt-dlp, or polls a queue producer in a hot loop.
  """

  import Ecto.Query, warn: false

  alias Pinchflat.Diagnostics.DatabaseDiagnostics
  alias Pinchflat.Diagnostics.QueueDiagnostics
  alias Pinchflat.Media.MediaItem
  alias Pinchflat.Profiles.MediaProfile
  alias Pinchflat.Repo
  alias Pinchflat.Sources.Source

  @failure_window_hours 24

  @doc """
  Returns the home-page system status: the data behind the Sources, Library,
  Activity and Database summary cards.
  """
  def get do
    db_stats = DatabaseDiagnostics.get_database_stats()
    media_storage = storage_stat(Application.fetch_env!(:pinchflat, :media_directory))
    database_storage = storage_stat(Path.dirname(DatabaseDiagnostics.database_filepath()))

    %{
      sources: source_counts(),
      library: library_counts(),
      queues: QueueDiagnostics.get_overall_queue_stats(),
      failed_recently: QueueDiagnostics.count_recent_failures(@failure_window_hours),
      failure_window_hours: @failure_window_hours,
      database: %{
        size_bytes: db_stats.total_bytes,
        reclaimable_bytes: db_stats.reclaimable_bytes,
        wal_bytes: db_stats.wal_file_bytes
      },
      storage: %{
        media: media_storage,
        database: database_storage,
        collocated: collocated?(media_storage, database_storage)
      },
      attention: QueueDiagnostics.get_job_attention_counts()
    }
  end

  defp source_counts do
    source =
      from(s in Source,
        select: %{
          total: count(s.id),
          enabled: fragment("COALESCE(SUM(CASE WHEN ? THEN 1 ELSE 0 END), 0)", s.enabled)
        }
      )
      |> Repo.one()

    Map.put(source, :profile_count, Repo.aggregate(MediaProfile, :count, :id))
  end

  defp library_counts do
    from(m in MediaItem,
      where: not is_nil(m.media_filepath),
      select: %{
        downloaded: count(m.id),
        size_bytes: fragment("COALESCE(SUM(?), 0)", m.media_size_bytes)
      }
    )
    |> Repo.one()
  end

  # Two directories are collocated when they resolve to the same mount point, in
  # which case the free-space readout is shown once (on Library) rather than
  # duplicated onto the Database card. Comparing resolved mount points rather than
  # path strings means eg a config dir nested under the media volume is still
  # recognised as the same disk.
  defp collocated?(%{mountpoint: mount}, %{mountpoint: mount}) when is_binary(mount), do: true
  defp collocated?(_media, _database), do: false

  defp storage_stat(path) do
    case disk_space_checker().space_info(path) do
      {:ok, info} ->
        %{
          path: path,
          available_bytes: info.available_bytes,
          total_bytes: info.total_bytes,
          used_percent: info.used_percent,
          mountpoint: info.mountpoint
        }

      :error ->
        %{path: path, available_bytes: nil, total_bytes: nil, used_percent: nil, mountpoint: nil}
    end
  end

  defp disk_space_checker do
    Application.get_env(:pinchflat, :disk_space_checker, Pinchflat.Diagnostics.DiskSpaceChecker)
  end
end
