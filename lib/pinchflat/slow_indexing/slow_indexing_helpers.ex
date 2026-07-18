defmodule Pinchflat.SlowIndexing.SlowIndexingHelpers do
  @moduledoc """
  Methods for performing slow indexing tasks and managing the indexing process.

  Many of these methods are made to be kickoff or be consumed by workers.
  """

  use Pinchflat.Media.MediaQuery

  require Logger

  alias Pinchflat.Repo
  alias Pinchflat.Media
  alias Pinchflat.Tasks
  alias Pinchflat.Sources
  alias Pinchflat.Sources.Source
  alias Pinchflat.Media.MediaItem
  alias Pinchflat.YtDlp.MediaCollection
  alias Pinchflat.Utils.FilesystemUtils
  alias Pinchflat.Downloading.DownloadingHelpers
  alias Pinchflat.SlowIndexing.FileFollowerServer
  alias Pinchflat.Downloading.DownloadOptionBuilder
  alias Pinchflat.SlowIndexing.MediaCollectionIndexingWorker

  alias Pinchflat.YtDlp.Media, as: YtDlpMedia

  @doc """
  Kills old indexing tasks and starts a new task to index the media collection.

  The job is delayed based on the source's `index_frequency_minutes` setting unless
  one of the following is true:
    - The `force` option is set to true
    - The source has never been indexed before
    - The source has been indexed before, but the last indexing job was more than
      `index_frequency_minutes` ago

  Returns {:ok, %Task{}}
  """
  def kickoff_indexing_task(%Source{} = source, job_args \\ %{}, job_opts \\ []) do
    job_offset_seconds = if job_args[:force], do: 0, else: calculate_job_offset_seconds(source)

    Tasks.delete_pending_tasks_for(source, "MediaCollectionIndexingWorker", include_executing: true)

    MediaCollectionIndexingWorker.kickoff_with_task(source, job_args, job_opts ++ [schedule_in: job_offset_seconds])
  end

  @doc """
  A helper method to delete all indexing-related tasks for a source.
  Optionally, you can include executing tasks in the deletion process.

  Returns :ok
  """
  def delete_indexing_tasks(%Source{} = source, opts \\ []) do
    include_executing = Keyword.get(opts, :include_executing, false)

    Tasks.delete_pending_tasks_for(source, "FastIndexingWorker", include_executing: include_executing)
    Tasks.delete_pending_tasks_for(source, "MediaCollectionIndexingWorker", include_executing: include_executing)
  end

  @doc """
  Given a media source, creates (indexes) the media by creating media_items for each
  media ID in the source. Afterward, kicks off a download task for each pending media
  item belonging to the source. Returns a list of media items or changesets
  (if the media item couldn't be created).

  Indexing is slow and usually returns a list of all media data at once for record creation.
  To help with this, we use a file follower to watch the file that yt-dlp writes to
  so we can create media items as they come in. This parallelizes the process and adds
  clarity to the user experience. This has a few things to be aware of which are documented
  below in the file watcher setup method.

  YouTube channels are indexed one tab at a time (videos, shorts, streams) as separate
  yt-dlp invocations. This matters because `--break-on-existing` aborts the whole yt-dlp
  process — not just the current tab — so indexing a bare channel URL with a download
  archive would stop at the first known video and never reach the shorts or streams tabs.
  Indexing each tab separately (with an archive filtered to that tab's content type) lets
  the early-abort optimization work per-tab without starving the others.

  Additionally, in the case of a repeat index we create a download archive file that
  contains some media IDs that we've indexed in the past. Note that this archive doesn't
  contain the most recent IDs but rather a subset of IDs that are offset by some amount.
  Practically, this means that we'll re-index a small handful of media that we've recently
  indexed, but this is a good thing since it'll let us pick up on any recent changes to the
  most recent media items.

  We don't create a download archive for playlists (only channels), nor do we create one if
  the indexing was forced by the user.

  NOTE: downloads are only enqueued if the source is set to download media. Downloads are
  also enqueued for ALL pending media items, not just the ones that were indexed in this
  job run. This should ensure that any stragglers are caught if, for some reason, they
  weren't enqueued or somehow got de-queued.

  Available options:
    - `was_forced`: Whether the indexing was forced by the user

  Returns [%MediaItem{} | %Ecto.Changeset{}]
  """
  def index_and_enqueue_download_for_media_items(%Source{} = source, opts \\ []) do
    # The media_profile is needed to determine the quality options to _then_ determine a more
    # accurate predicted filepath
    source = Repo.preload(source, [:media_profile])
    # See the method definition below for more info on how file watchers work
    # (important reading if you're not familiar with it)
    {:ok, media_attributes} = setup_file_watcher_and_kickoff_indexing(source, opts)
    # Reload because the source may have been updated during the (long-running) indexing process
    # and important settings like `download_media` may have changed.
    source = Repo.reload!(source)

    result =
      Enum.map(media_attributes, fn media_attrs ->
        case Media.create_media_item_from_backend_attrs(source, media_attrs) do
          {:ok, media_item} -> media_item
          {:error, changeset} -> changeset
        end
      end)

    Sources.update_source(source, %{last_indexed_at: DateTime.utc_now()})
    DownloadingHelpers.enqueue_pending_download_tasks(source)

    result
  end

  # The file follower is a GenServer that watches a file for new lines and
  # processes them. This works well, but we have to be resilliant to partially-written
  # lines (ie: you should gracefully fail if you can't parse a line).
  #
  # This works in-tandem with the normal (blocking) media indexing behaviour. When
  # the `setup_file_watcher_and_kickoff_indexing` method completes it'll return the
  # FULL result to the caller for parsing. Ideally, every item in the list will have already
  # been processed by the file follower, but if not, the caller handles creation
  # of any media items that were missed/initially failed.
  #
  # It attempts a graceful shutdown of the file follower after the indexing is done,
  # but the FileFollowerServer will also stop itself if it doesn't see any activity
  # for a sufficiently long time.
  defp setup_file_watcher_and_kickoff_indexing(source, opts) do
    was_forced = Keyword.get(opts, :was_forced, false)
    should_use_cookies = Sources.use_cookies?(source, :indexing)

    base_command_opts =
      [output: DownloadOptionBuilder.build_output_path_for(source)] ++
        DownloadOptionBuilder.build_quality_options_for(source)

    results =
      Enum.map(indexing_urls_for(source), fn {url, content_type} ->
        command_opts =
          base_command_opts ++
            build_download_archive_options(source, was_forced, content_type) ++
            build_index_cutoff_options(source, content_type)

        run_indexing_command(source, url, command_opts, should_use_cookies)
      end)

    # A channel can legitimately lack a shorts or streams tab (yt-dlp errors out
    # on those), so a failed URL only fails the index if no URL succeeded at all.
    # Tabs shouldn't overlap in content, but dedupe across them just in case.
    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {[], [first_error | _]} ->
        first_error

      {successes, _} ->
        media_attributes =
          successes
          |> Enum.flat_map(fn {:ok, media_attributes} -> media_attributes end)
          |> Enum.uniq_by(& &1.media_id)

        {:ok, media_attributes}
    end
  end

  defp run_indexing_command(source, url, command_opts, should_use_cookies) do
    {:ok, pid} = FileFollowerServer.start_link()

    handler = fn filepath -> setup_file_follower_watcher(pid, filepath, source) end

    # Exit code 1 is declared as expected so the runner logs it at debug instead
    # of error — failures are logged here instead, where we can tell a channel
    # legitimately missing a shorts/streams tab apart from a real error.
    runner_opts = [
      file_listener_handler: handler,
      use_cookies: should_use_cookies,
      expected_exit_codes: [1]
    ]

    result = MediaCollection.get_media_attributes_for_collection(url, command_opts, runner_opts)

    FileFollowerServer.stop(pid)

    case result do
      {:ok, media_attributes} ->
        {:ok, media_attributes}

      err ->
        log_indexing_failure(url, err)
        err
    end
  end

  # A channel not having a shorts/streams/live tab is a normal state of affairs,
  # not something to warn about on every scheduled index.
  defp log_indexing_failure(url, {:error, message, _status} = err) when is_binary(message) do
    if message =~ ~r/does not have a \S+ tab/ do
      Logger.debug("Indexing skipped for #{url}: #{String.trim(message)}")
    else
      Logger.warning("Indexing failed for #{url}: #{inspect(err)}")
    end
  end

  defp log_indexing_failure(url, err) do
    Logger.warning("Indexing failed for #{url}: #{inspect(err)}")
  end

  # YouTube channels are indexed one content tab at a time because `--break-on-existing`
  # aborts the entire yt-dlp process, not just the current tab — indexing a bare channel
  # URL with a download archive stops at the first known video and never reaches the
  # shorts or streams tabs (see moduledoc). Channels whose URL already names a tab are
  # respected as-is, and playlists/non-YouTube sources are passed through untouched.
  defp indexing_urls_for(%Source{collection_type: :channel} = source) do
    explicit_tab = explicit_channel_tab(source.original_url)

    cond do
      not String.contains?(source.original_url, "youtube.com") ->
        [{source.original_url, :all}]

      explicit_tab ->
        [{source.original_url, explicit_tab}]

      true ->
        Enum.map([:videos, :shorts, :streams], fn tab ->
          {"https://www.youtube.com/channel/#{source.collection_id}/#{tab}", tab}
        end)
    end
  end

  defp indexing_urls_for(source), do: [{source.original_url, :all}]

  defp explicit_channel_tab(url) do
    case Regex.run(~r{youtube\.com/.+/(videos|shorts|streams|live)/?(?:\?.*)?$}, url) do
      [_, "videos"] -> :videos
      [_, "shorts"] -> :shorts
      [_, "streams"] -> :streams
      [_, "live"] -> :streams
      _ -> nil
    end
  end

  defp setup_file_follower_watcher(pid, filepath, source) do
    FileFollowerServer.watch_file(pid, filepath, fn line ->
      case Phoenix.json_library().decode(line) do
        {:ok, media_attrs} ->
          Logger.debug("FileFollowerServer Handler: Got media attributes: #{inspect(media_attrs)}")

          media_struct = YtDlpMedia.response_to_struct(media_attrs)
          create_media_item_and_enqueue_download(source, media_struct)

        err ->
          Logger.debug("FileFollowerServer Handler: Error decoding JSON: #{inspect(err)}")

          err
      end
    end)
  end

  defp create_media_item_and_enqueue_download(source, media_attrs) do
    # Reload because the source may have been updated during the (long-running) indexing process
    # and important settings like `download_media` may have changed.
    source = Repo.reload!(source)

    case Media.create_media_item_from_backend_attrs(source, media_attrs) do
      {:ok, %MediaItem{} = media_item} ->
        DownloadingHelpers.kickoff_download_if_pending(media_item)

      {:error, changeset} ->
        changeset
    end
  end

  # Find the difference between the current time and the last time the source was indexed
  defp calculate_job_offset_seconds(%Source{last_indexed_at: nil}), do: 0

  defp calculate_job_offset_seconds(source) do
    offset_seconds = DateTime.diff(DateTime.utc_now(), source.last_indexed_at, :second)
    index_frequency_seconds = source.index_frequency_minutes * 60

    max(0, index_frequency_seconds - offset_seconds)
  end

  # The download archive file works in tandem with --break-on-existing to stop
  # yt-dlp once we've hit media items we've already indexed. But we generate
  # this list with a bit of an offset so we do intentionally re-scan some media
  # items to pick up any recent changes (see `get_media_items_for_download_archive`).
  # The archive only contains media matching the content tab being indexed —
  # a short in the videos tab's archive would never match anything and would
  # eat into the re-scan buffer.
  #
  # From there, we format the media IDs in the way that yt-dlp expects (ie: "<extractor> <media_id>")
  # and return the filepath to the caller.
  defp create_download_archive_file(source, content_type) do
    tmpfile = FilesystemUtils.generate_metadata_tmpfile(:txt)

    archive_contents =
      source
      |> get_media_items_for_download_archive(content_type)
      |> Enum.map_join("\n", fn media_item -> "youtube #{media_item.media_id}" end)

    case File.write(tmpfile, archive_contents) do
      :ok -> {:ok, tmpfile}
      err -> err
    end
  end

  # Sorting by `uploaded_at` is important because we want to re-index the most recent
  # media items first but there is no guarantee of any correlation between ID and uploaded_at.
  #
  # The offset is important because we want to re-index some media items that we've
  # recently indexed to pick up on any changes. The limit is because we want this mechanism
  # to work even if, for example, the video we were using as a stopping point was deleted.
  # It's not a perfect system, but it should do well enough.
  #
  # The chosen limit and offset are arbitary, independent, and vibes-based. Feel free to
  # tweak as-needed
  defp get_media_items_for_download_archive(source, content_type) do
    MediaQuery.new()
    |> where(^MediaQuery.for_source(source))
    |> where(^content_type_filter(content_type))
    |> order_by(desc: :uploaded_at)
    |> limit(50)
    |> offset(20)
    |> Repo.all()
  end

  defp content_type_filter(:videos), do: dynamic([mi], mi.short_form_content == false and mi.livestream == false)
  defp content_type_filter(:shorts), do: dynamic([mi], mi.short_form_content == true)
  defp content_type_filter(:streams), do: dynamic([mi], mi.livestream == true)
  defp content_type_filter(:all), do: dynamic(true)

  # `--break-match-filters` aborts the crawl the moment it reaches a video older
  # than the source's indexing cutoff date. Unlike the download archive (which is
  # skipped on first/forced indexes), this applies to every index — the first crawl
  # of a large channel is exactly where it saves the most time.
  #
  # Early abort is only safe when the listing is newest-first, which is only
  # guaranteed for YouTube channel tabs — playlists are ordered arbitrarily and
  # non-YouTube sources make no ordering promise. Both of those index with an
  # `:all` content type, so matching on tab content types gates this to YouTube
  # channels.
  #
  # yt-dlp ORs repeated match filters, so this breaks only when a video HAS an
  # upload date and it's older than the cutoff. The `!upload_date` clause keeps
  # entries without one (eg: upcoming premieres) from tripping the break.
  defp build_index_cutoff_options(%Source{index_cutoff_date: %Date{} = cutoff_date}, content_type)
       when content_type in [:videos, :shorts, :streams] do
    formatted_date = Calendar.strftime(cutoff_date, "%Y%m%d")

    [
      break_match_filters: "upload_date >= #{formatted_date}",
      break_match_filters: "!upload_date"
    ]
  end

  defp build_index_cutoff_options(_source, _content_type), do: []

  # The download archive isn't useful for playlists (since those are ordered arbitrarily)
  # and we don't want to use it if the indexing was forced by the user. In other words,
  # only create an archive for channels that are being indexed as part of their regular
  # indexing schedule. The first indexing pass should also not create an archive.
  defp build_download_archive_options(%Source{collection_type: :playlist}, _was_forced, _content_type), do: []
  defp build_download_archive_options(%Source{last_indexed_at: nil}, _was_forced, _content_type), do: []
  defp build_download_archive_options(_source, true, _content_type), do: []

  # The archive is an optimization, so if the file can't be written we index
  # without one rather than passing a bad option to yt-dlp or failing the run.
  defp build_download_archive_options(source, _was_forced, content_type) do
    case create_download_archive_file(source, content_type) do
      {:ok, archive_file} ->
        [:break_on_existing, download_archive: archive_file]

      {:error, err} ->
        Logger.warning("Unable to write download archive file for source ##{source.id}: #{inspect(err)}")

        []
    end
  end
end
