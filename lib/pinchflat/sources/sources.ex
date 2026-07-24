defmodule Pinchflat.Sources do
  @moduledoc """
  The Sources context.
  """

  import Ecto.Query, warn: false
  use Pinchflat.Media.MediaQuery

  alias Pinchflat.Repo
  alias Pinchflat.Media
  alias Pinchflat.Tasks
  alias Pinchflat.Sources.Source
  alias Pinchflat.Profiles.MediaProfile
  alias Pinchflat.YtDlp.MediaCollection
  alias Pinchflat.Metadata.SourceMetadata
  alias Pinchflat.Podcasts.PodcastExportWorker
  alias Pinchflat.Utils.StringUtils
  alias Pinchflat.Utils.FilesystemUtils
  alias Pinchflat.Downloading.DownloadingHelpers
  alias Pinchflat.SlowIndexing.SlowIndexingHelpers
  alias Pinchflat.FastIndexing.FastIndexingHelpers
  alias Pinchflat.Metadata.SourceMetadataStorageWorker

  @doc """
  Returns the relevant output path template for a source. Podcast sources always
  use the flat, slug-rooted layout (so the podcast library can be served in place)
  — this wins even over a source override, since the static server and generated
  feed URLs depend on that layout. Otherwise a source override wins, falling back
  to the media profile's template.

  Returns binary()
  """
  def output_path_template(source) do
    source = Repo.preload(source, :media_profile)
    media_profile = source.media_profile

    cond do
      MediaProfile.podcast?(media_profile) -> podcast_output_path_template()
      source.output_path_template_override -> source.output_path_template_override
      true -> media_profile.output_path_template
    end
  end

  @doc """
  The output path template used for podcast sources: a single readable folder per
  podcast (the slug), holding the episode files (and, alongside them, the
  generated `feed.xml` and `cover`). Filenames are deliberately minimal — date
  for browsability, ID for uniqueness — since episode titles live in the feed
  and simple names make for simple, robust enclosure URLs.

  Returns binary()
  """
  def podcast_output_path_template do
    "{{ source_slug }}/{{ upload_yyyy_mm_dd }} {{ id }}.{{ ext }}"
  end

  @doc """
  Returns a boolean indicating whether or not cookies should be used for a given operation.

  Returns boolean()
  """
  def use_cookies?(source, operation) when operation in [:indexing, :downloading, :metadata, :error_recovery] do
    case source.cookie_behaviour do
      :disabled -> false
      :all_operations -> true
      :when_needed -> operation in [:indexing, :error_recovery]
    end
  end

  @doc """
  Returns the list of sources. Returns [%Source{}, ...]
  """
  def list_sources do
    Repo.all(Source)
  end

  @doc """
  Returns the list of sources for a media_profile.

  Returns [%Source{}, ...]
  """
  def list_sources_for(%MediaProfile{} = media_profile) do
    Repo.all(from s in Source, where: s.media_profile_id == ^media_profile.id)
  end

  @doc """
  Gets a single source.

  Returns %Source{}. Raises `Ecto.NoResultsError` if the Source does not exist.
  """
  def get_source!(id), do: Repo.get!(Source, id)

  @doc """
  Creates a source. May attempt to pull additional source details from the
  original_url (if provided). Will attempt to start indexing the source's
  media if successfully inserted.

  Runs an initial `change_source` check to ensure most of the source is valid
  before making an expensive API call. Runs it through `Repo.insert` even
  though we know it's going to fail so it picks up any addl. database errors
  and fulfills our return contract.

  You can pass options to control the behavior of the function:
    - `run_post_commit_tasks` (default: true) - If false, the function will not
      enqueue any tasks in `commit_and_handle_tasks`.

  Returns {:ok, %Source{}} | {:error, %Ecto.Changeset{}}
  """
  def create_source(attrs, opts \\ []) do
    case change_source(%Source{}, attrs, :initial) do
      %Ecto.Changeset{valid?: true} ->
        %Source{}
        |> maybe_change_source_from_url(attrs)
        |> maybe_change_indexing_frequency()
        |> maybe_assign_slug()
        |> commit_and_handle_tasks(opts)

      changeset ->
        Repo.insert(changeset)
    end
  end

  @doc """
  Updates a source. May attempt to pull additional source details from the
  original_url (if changed). May attempt to start indexing the source's
  media if the indexing frequency has been changed.

  Existing indexing tasks will be cancelled if the indexing frequency has been
  changed (logic in `SlowIndexingHelpers.kickoff_indexing_task`)

  Runs an initial `change_source` check to ensure most of the source is valid
  before making an expensive API call. Runs it through `Repo.update` even
  though we know it's going to fail so it picks up any addl. database errors
  and fulfills our return contract.

  You can pass options to control the behavior of the function:
    - `run_post_commit_tasks` (default: true) - If false, the function will not
      enqueue any tasks in `commit_and_handle_tasks`.

  Returns {:ok, %Source{}} | {:error, %Ecto.Changeset{}}
  """
  def update_source(%Source{} = source, attrs, opts \\ []) do
    case change_source(source, attrs, :initial) do
      %Ecto.Changeset{valid?: true} ->
        source
        |> maybe_change_source_from_url(attrs)
        |> maybe_change_indexing_frequency()
        |> maybe_assign_slug()
        |> commit_and_handle_tasks(opts)

      changeset ->
        Repo.update(changeset)
    end
  end

  @doc """
  Deletes a source, its media items, and its associated tasks (of any state).
  Can optionally delete the source's media files.

  Returns {:ok, %Source{}} | {:error, %Ecto.Changeset{}}
  """
  def delete_source(%Source{} = source, opts \\ []) do
    delete_files = Keyword.get(opts, :delete_files, false)
    Tasks.delete_tasks_for(source)

    MediaQuery.new()
    |> where(^MediaQuery.for_source(source))
    |> Repo.all()
    |> Enum.each(fn media_item ->
      # `handle_source_deleted` below prunes the whole podcast export
      # directory, so per-item export notifications would only add noise
      Media.delete_media_item(media_item, delete_files: delete_files, notify_podcast_export: false)
    end)

    if delete_files do
      delete_source_files(source)
    end

    delete_internal_metadata_files(source)

    case Repo.delete(source) do
      {:ok, deleted_source} ->
        # Cleanup is queued (not run here) so it serializes behind any export
        # or sweep already running with a pre-deletion snapshot of this source
        PodcastExportWorker.kickoff_deletion(deleted_source)
        {:ok, deleted_source}

      err ->
        err
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking source changes.
  """
  def change_source(%Source{} = source, attrs \\ %{}, validation_stage \\ :pre_insert) do
    Source.changeset(source, attrs, validation_stage)
  end

  # Assigns a stable, unique, readable slug the first time a source is saved.
  # It's the source's podcast folder/URL name, so it's kept across renames (only
  # set when absent) and made unique by suffixing so two same-named sources — or
  # a name that slugs to nothing — never collide or fail to insert.
  defp maybe_assign_slug(changeset) do
    if Ecto.Changeset.get_field(changeset, :slug) do
      changeset
    else
      base = Ecto.Changeset.get_field(changeset, :custom_name) || "podcast"
      Ecto.Changeset.put_change(changeset, :slug, unique_slug(base))
    end
  end

  defp unique_slug(base) do
    slug =
      case StringUtils.to_slug(base) do
        "" -> "podcast"
        slug -> slug
      end

    ensure_unique_slug(slug, slug, 2)
  end

  defp ensure_unique_slug(candidate, base, next_suffix) do
    if Repo.exists?(from(s in Source, where: s.slug == ^candidate)) do
      ensure_unique_slug("#{base}-#{next_suffix}", base, next_suffix + 1)
    else
      candidate
    end
  end

  # NOTE: When operating in the ideal path, this effectively adds an API call
  # to the source creation/update process. Should be used only when needed.
  defp maybe_change_source_from_url(%Source{} = source, attrs) do
    case change_source(source, attrs) do
      %Ecto.Changeset{changes: %{original_url: _}} = changeset ->
        add_source_details_to_changeset(source, changeset)

      changeset ->
        changeset
    end
  end

  defp delete_source_files(source) do
    mapped_struct = Map.from_struct(source)

    Source.filepath_attributes()
    |> Enum.map(fn field -> mapped_struct[field] end)
    |> Enum.filter(&is_binary/1)
    |> Enum.each(&FilesystemUtils.delete_file_and_remove_empty_directories/1)
  end

  defp delete_internal_metadata_files(source) do
    metadata = Repo.preload(source, :metadata).metadata || %SourceMetadata{}
    mapped_struct = Map.from_struct(metadata)

    SourceMetadata.filepath_attributes()
    |> Enum.map(fn field -> mapped_struct[field] end)
    |> Enum.filter(&is_binary/1)
    |> Enum.each(&FilesystemUtils.delete_file_and_remove_empty_directories/1)
  end

  defp add_source_details_to_changeset(source, changeset) do
    original_url = changeset.changes.original_url
    should_use_cookies = Ecto.Changeset.get_field(changeset, :cookie_behaviour) == :all_operations
    # Skipping sleep interval since this is UI blocking and we want to keep this as fast as possible
    addl_opts = [use_cookies: should_use_cookies, skip_sleep_interval: true]

    case MediaCollection.get_source_details(original_url, [], addl_opts) do
      {:ok, source_details} ->
        add_source_details_by_collection_type(source, changeset, source_details)

      err ->
        runner_error =
          case err do
            {:error, error_msg, _status_code} -> error_msg
            {:error, error_msg} -> error_msg
          end

        Ecto.Changeset.add_error(
          changeset,
          :original_url,
          "could not fetch source details from URL",
          error: runner_error
        )
    end
  end

  defp add_source_details_by_collection_type(source, changeset, source_details) do
    %Ecto.Changeset{changes: changes} = changeset

    collection_changes =
      if source_details.playlist_id == source_details.channel_id do
        %{
          collection_type: :channel,
          collection_id: source_details.channel_id,
          collection_name: source_details.channel_name
        }
      else
        %{
          collection_type: :playlist,
          collection_id: source_details.playlist_id,
          collection_name: source_details.playlist_name
        }
      end

    change_source(source, Map.merge(changes, collection_changes))
  end

  defp maybe_change_indexing_frequency(changeset) do
    fast_index = Ecto.Changeset.get_field(changeset, :fast_index)

    if fast_index do
      Ecto.Changeset.put_change(
        changeset,
        :index_frequency_minutes,
        Source.index_frequency_when_fast_indexing()
      )
    else
      changeset
    end
  end

  defp commit_and_handle_tasks(changeset, opts) do
    run_post_commit_tasks = Keyword.get(opts, :run_post_commit_tasks, true)

    case Repo.insert_or_update(changeset) do
      {:ok, %Source{} = source} ->
        if run_post_commit_tasks do
          maybe_handle_media_tasks(changeset, source)
          maybe_run_indexing_task(changeset, source)
          maybe_run_metadata_storage_task(changeset, source)
          maybe_run_podcast_export_task(changeset, source)
        end

        {:ok, source}

      err ->
        err
    end
  end

  # If the source is new (ie: not persisted), do nothing
  defp maybe_handle_media_tasks(%{data: %{__meta__: %{state: state}}}, _source) when state != :loaded do
    :ok
  end

  # If the source is NOT new (ie: updated),
  # enqueue or dequeue media download tasks as necessary.
  defp maybe_handle_media_tasks(changeset, source) do
    current_changes = changeset.changes
    applied_changes = Ecto.Changeset.apply_changes(changeset)

    # We need both current_changes and applied_changes to determine
    # the course of action to take. For example, we only care if a source is supposed
    # to be `enabled` or not - we don't care if that information comes from the
    # current changes or if that's how it already was in the database.
    # Rephrased, we're essentially using it in place of `get_field/2`
    case {current_changes, applied_changes} do
      {%{download_media: true}, %{enabled: true}} ->
        DownloadingHelpers.enqueue_pending_download_tasks(source)

      {%{enabled: true}, %{download_media: true}} ->
        DownloadingHelpers.enqueue_pending_download_tasks(source)

      {%{download_media: false}, _} ->
        DownloadingHelpers.dequeue_pending_download_tasks(source)

      {%{enabled: false}, _} ->
        DownloadingHelpers.dequeue_pending_download_tasks(source)

      _ ->
        nil
    end

    :ok
  end

  defp maybe_run_indexing_task(changeset, source) do
    case changeset.data do
      # If the changeset is new (not persisted), attempt indexing no matter what
      %{__meta__: %{state: :built}} ->
        SlowIndexingHelpers.kickoff_indexing_task(source)

        if Ecto.Changeset.get_field(changeset, :fast_index) do
          FastIndexingHelpers.kickoff_indexing_task(source)
        end

      # If the record has been persisted, only run indexing if the
      # indexing frequency has been changed and is now greater than 0
      %{__meta__: %{state: :loaded}} ->
        maybe_update_slow_indexing_task(changeset, source)
        maybe_update_fast_indexing_task(changeset, source)
    end
  end

  defp maybe_run_metadata_storage_task(changeset, source) do
    case {changeset.data, changeset.changes} do
      # If the changeset is new (not persisted), fetch metadata no matter what
      {%{__meta__: %{state: :built}}, _} ->
        SourceMetadataStorageWorker.kickoff_with_task(source)

      # If the record has been persisted, only fetch metadata if the
      # original_url has changed
      {_, %{original_url: _}} ->
        SourceMetadataStorageWorker.kickoff_with_task(source)

      _ ->
        :ok
    end
  end

  # Re-export the static podcast feed when a change would alter its contents
  # or whether it should exist at all. The worker itself no-ops for sources
  # that aren't (and never were) export-enabled
  defp maybe_run_podcast_export_task(changeset, source) do
    relevant_fields = ~w(custom_name description enabled original_url slug media_profile_id)a

    if Enum.any?(relevant_fields, &Map.has_key?(changeset.changes, &1)) do
      PodcastExportWorker.kickoff(source)
    end

    :ok
  end

  defp maybe_update_slow_indexing_task(changeset, source) do
    # See comment in `maybe_handle_media_tasks` as to why we need these
    current_changes = changeset.changes
    applied_changes = Ecto.Changeset.apply_changes(changeset)

    case {current_changes, applied_changes} do
      # Widening the index cutoff further into the past means videos that were
      # previously out of range are now in range, so we need to re-crawl. This
      # must be a *forced* index: a normal scheduled index builds a
      # `--break-on-existing` download archive that would halt at the first known
      # video and never reach the newly-in-range older ones (see
      # `SlowIndexingHelpers.build_download_archive_options/3`). Narrowing the
      # cutoff needs no action since those items are already indexed.
      {%{index_cutoff_date: _}, %{enabled: true, index_frequency_minutes: mins}}
      when mins > 0 ->
        if index_cutoff_widened?(changeset) do
          SlowIndexingHelpers.kickoff_indexing_task(source, %{force: true})
        else
          :ok
        end

      {%{index_frequency_minutes: mins}, %{enabled: true}} when mins > 0 ->
        SlowIndexingHelpers.kickoff_indexing_task(source)

      {%{enabled: true}, %{index_frequency_minutes: mins}} when mins > 0 ->
        SlowIndexingHelpers.kickoff_indexing_task(source)

      {%{index_frequency_minutes: _}, _} ->
        SlowIndexingHelpers.delete_indexing_tasks(source, include_executing: true)

      {%{enabled: false}, _} ->
        SlowIndexingHelpers.delete_indexing_tasks(source, include_executing: true)

      _ ->
        :ok
    end
  end

  # A cutoff is "widened" when the new date reaches further into the past than
  # the old one (or is removed entirely, making indexing unbounded). Removing a
  # cutoff (-> nil) always widens; adding one to a previously unbounded source
  # (nil -> date) only narrows and needs no re-index.
  defp index_cutoff_widened?(changeset) do
    old_cutoff = changeset.data.index_cutoff_date
    new_cutoff = Ecto.Changeset.get_field(changeset, :index_cutoff_date)

    case {old_cutoff, new_cutoff} do
      {_, nil} -> not is_nil(old_cutoff)
      {nil, _} -> false
      {old, new} -> Date.compare(new, old) == :lt
    end
  end

  defp maybe_update_fast_indexing_task(changeset, source) do
    # See comment in `maybe_handle_media_tasks` as to why we need these
    current_changes = changeset.changes
    applied_changes = Ecto.Changeset.apply_changes(changeset)

    # This technically could be simplified since `maybe_update_slow_indexing_task`
    # has some overlap re: deleting pending tasks, but I'm keeping it separate
    # for clarity and explicitness.
    case {current_changes, applied_changes} do
      {%{fast_index: true}, %{enabled: true}} ->
        FastIndexingHelpers.kickoff_indexing_task(source)

      {%{enabled: true}, %{fast_index: true}} ->
        FastIndexingHelpers.kickoff_indexing_task(source)

      {%{fast_index: false}, _} ->
        Tasks.delete_pending_tasks_for(source, "FastIndexingWorker", include_executing: true)

      {%{enabled: false}, _} ->
        Tasks.delete_pending_tasks_for(source, "FastIndexingWorker", include_executing: true)

      _ ->
        :ok
    end
  end
end
