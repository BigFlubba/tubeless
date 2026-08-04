defmodule PinchflatWeb.Sources.SourceController do
  use PinchflatWeb, :controller
  use Pinchflat.Sources.SourcesQuery

  alias Pinchflat.Repo
  alias Pinchflat.Tasks
  alias Pinchflat.Sources
  alias Pinchflat.Reconciliation
  alias Pinchflat.Sources.Source
  alias Pinchflat.Profiles.MediaProfile
  alias Pinchflat.Media.FileSyncingWorker
  alias Pinchflat.Sources.SourceDeletionWorker
  alias Pinchflat.Downloading.DownloadingHelpers
  alias Pinchflat.SlowIndexing.SlowIndexingHelpers
  alias Pinchflat.Metadata.SourceMetadataStorageWorker

  def index(conn, _params) do
    render(conn, :index)
  end

  def new(conn, params) do
    # This lets me preload the settings from another source for more efficient creation
    %Source{} =
      cs_struct =
      case to_string(params["template_id"]) do
        # A fresh source pre-selects the configured default cookie behaviour;
        # cloning from a template keeps that template's cookie behaviour instead
        "" -> %Source{cookie_behaviour: default_cookie_behaviour()}
        template_id -> Repo.get(Source, template_id) || %Source{cookie_behaviour: default_cookie_behaviour()}
      end

    render(conn, :new,
      media_profiles: media_profiles(),
      layout: get_onboarding_layout(),
      # Most of these don't actually _need_ to be nullified at this point,
      # but if I don't do it now I know it'll bite me
      changeset:
        Sources.change_source(%Source{
          cs_struct
          | id: nil,
            uuid: nil,
            custom_name: nil,
            description: nil,
            collection_name: nil,
            collection_id: nil,
            collection_type: nil,
            original_url: nil,
            marked_for_deletion_at: nil
        })
    )
  end

  def create(conn, %{"source" => source_params}) do
    case Sources.create_source(source_params) do
      {:ok, source} ->
        redirect_location =
          if Settings.get!(:onboarding), do: ~p"/?onboarding=1", else: ~p"/sources/#{source}"

        conn
        |> put_flash(:info, "Source created successfully.")
        |> redirect(to: redirect_location)

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new,
          changeset: changeset,
          media_profiles: media_profiles(),
          layout: get_onboarding_layout()
        )
    end
  end

  def show(conn, %{"id" => id}) do
    source = Repo.preload(Sources.get_source!(id), [:media_profile, :metadata])

    pending_tasks =
      source
      |> Tasks.list_tasks_for(nil, [:executing, :available, :scheduled, :retryable])
      |> Repo.preload(:job)

    tab_counts = Sources.tab_counts(source)
    # Both the header pill and the blocking-conditions banner need this and it
    # costs a query, so it's resolved once and injected into both. Neither
    # consults it for a disabled source, so don't pay for one.
    indexing_failed? = source.enabled && Sources.indexing_failing?(source)

    render(conn, :show,
      source: source,
      pending_tasks: pending_tasks,
      activity: Tasks.list_recent_activity_for_source(source),
      # Queried separately from the (capped) recent history so a failure can't be
      # pushed out of view by newer successful jobs while the header stays red
      unresolved_activity: Tasks.list_unresolved_activity_for_source(source),
      # Counts the source's own tasks AND its media items' download tasks, unlike
      # `pending_tasks` (source-attached only, used for the "next check" time)
      in_flight_activity_count: Tasks.count_in_flight_activity_for_source(source),
      tab_counts: tab_counts,
      # Reuses the counts already loaded for the tabs rather than re-querying
      blocking_conditions:
        Sources.blocking_conditions(source, tab_counts: tab_counts, indexing_failed?: indexing_failed?),
      source_status: Sources.status(source, indexing_failed?: indexing_failed?)
    )
  end

  def edit(conn, %{"id" => id}) do
    source = Sources.get_source!(id)
    changeset = Sources.change_source(source)

    render(conn, :edit, source: source, changeset: changeset, media_profiles: media_profiles())
  end

  def update(conn, %{"id" => id, "source" => source_params}) do
    source = Sources.get_source!(id)

    case Sources.update_source(source, source_params) do
      {:ok, source} ->
        # Source changes (e.g. an output-path override) can alter predicted paths,
        # invalidating any staged reconcile plan
        Reconciliation.mark_ready_plans_stale()

        conn
        |> put_flash(:info, "Source updated successfully.")
        |> redirect(to: ~p"/sources/#{source}")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit,
          source: source,
          changeset: changeset,
          media_profiles: media_profiles()
        )
    end
  end

  def delete(conn, %{"id" => id} = params) do
    # This awkward comparison converts the string to a boolean
    delete_files = Map.get(params, "delete_files", "") == "true"
    source = Sources.get_source!(id)

    {:ok, _} = Sources.update_source(source, %{marked_for_deletion_at: DateTime.utc_now()})
    SourceDeletionWorker.kickoff(source, %{delete_files: delete_files})

    conn
    |> put_flash(:info, "Source deletion started. This may take a while to complete.")
    |> redirect(to: ~p"/sources")
  end

  def force_download_pending(conn, %{"source_id" => id}) do
    wrap_forced_action(
      conn,
      id,
      "Forcing download of pending media items.",
      &DownloadingHelpers.enqueue_pending_download_tasks/1,
      require_enabled: true
    )
  end

  def force_redownload(conn, %{"source_id" => id}) do
    wrap_forced_action(
      conn,
      id,
      "Forcing re-download of downloaded media items.",
      &DownloadingHelpers.kickoff_redownload_for_existing_media/1,
      require_enabled: true
    )
  end

  @image_types %{"banner" => :banner, "poster" => :poster, "fanart" => :fanart}

  def image(conn, %{"source_id" => id, "image_type" => image_type}) do
    source = Sources.get_source!(id)
    filepath = @image_types[image_type] && Sources.image_filepath(source, @image_types[image_type])

    if servable_image?(filepath) do
      conn
      |> put_resp_content_type(MIME.from_path(filepath))
      |> send_file(200, filepath)
    else
      send_resp(conn, 404, "Image not found")
    end
  end

  # Defense in depth for the image route: only ever serve a regular file that
  # canonically resolves beneath one of the app-managed media/metadata directories.
  # Casting of the *_filepath columns is already restricted to internal writers,
  # but this guarantees the route can never read an arbitrary file even if a bad
  # path were somehow persisted.
  defp servable_image?(nil), do: false

  defp servable_image?(filepath) do
    canonical = canonical_path(filepath)

    File.regular?(canonical) &&
      Enum.any?(managed_image_dirs(), fn dir ->
        canonical == dir or String.starts_with?(canonical, dir <> "/")
      end)
  end

  defp managed_image_dirs do
    [
      Application.get_env(:pinchflat, :media_directory),
      Application.get_env(:pinchflat, :metadata_directory)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&canonical_path/1)
  end

  # `Path.expand/1` is purely lexical: it collapses `..` but will happily hand back
  # a path that leaves the managed directories through a symlink. Resolve every
  # component for real so the prefix check above means what it says. The managed
  # directories go through this too, so a legitimately symlinked media volume
  # still matches.
  @max_symlink_hops 8

  defp canonical_path(path) do
    path
    |> Path.expand()
    |> Path.split()
    |> Enum.reduce("/", fn component, resolved ->
      resolved |> Path.join(component) |> follow_link(@max_symlink_hops)
    end)
  end

  defp follow_link(path, 0), do: path

  defp follow_link(path, hops_left) do
    case File.read_link(path) do
      {:ok, target} -> path |> Path.dirname() |> then(&Path.expand(target, &1)) |> follow_link(hops_left - 1)
      {:error, _} -> path
    end
  end

  def toggle_enabled(conn, %{"source_id" => id}) do
    source = Sources.get_source!(id)

    case Sources.update_source(source, %{enabled: !source.enabled}) do
      {:ok, updated} ->
        conn
        |> put_flash(:info, if(updated.enabled, do: "Source resumed.", else: "Source paused."))
        |> redirect(to: ~p"/sources/#{updated}")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Couldn't change this source's state. Try again from its edit page.")
        |> redirect(to: ~p"/sources/#{source}")
    end
  end

  def check_for_new_videos(conn, %{"source_id" => id}) do
    wrap_forced_action(
      conn,
      id,
      "Checking for new videos.",
      # Non-forced (incremental, break-on-existing) index, run immediately rather
      # than waiting for the source's next scheduled check — but never at the cost
      # of an index that's already underway
      &SlowIndexingHelpers.kickoff_incremental_check/1,
      require_enabled: true
    )
  end

  def force_index(conn, %{"source_id" => id}) do
    wrap_forced_action(
      conn,
      id,
      "Full re-index enqueued.",
      &SlowIndexingHelpers.kickoff_indexing_task(&1, %{force: true}),
      require_enabled: true
    )
  end

  def force_metadata_refresh(conn, %{"source_id" => id}) do
    wrap_forced_action(
      conn,
      id,
      "Metadata refresh enqueued.",
      &SourceMetadataStorageWorker.kickoff_with_task/1
    )
  end

  def sync_files_on_disk(conn, %{"source_id" => id}) do
    wrap_forced_action(
      conn,
      id,
      "File sync enqueued.",
      &FileSyncingWorker.kickoff_with_task/1
    )
  end

  defp wrap_forced_action(conn, source_id, message, fun, opts \\ []) do
    source = Sources.get_source!(source_id)

    # A paused (disabled) source has had its indexing/download tasks removed;
    # actions that would re-enqueue that work must refuse to run so the header
    # "Paused" state can't be silently undone (resume the source first).
    if Keyword.get(opts, :require_enabled, false) && !source.enabled do
      conn
      |> put_flash(:error, "Resume this source before running that action.")
      |> redirect(to: ~p"/sources/#{source}")
    else
      {level, flash} =
        case fun.(source) do
          # An action can decline the work (rather than fail) and say so — currently
          # only "check for new videos", which won't interrupt a running index
          {:error, :already_running} ->
            {:info, "This source is already being indexed — that run will finish on its own."}

          # Anything else that failed to enqueue (a rejected changeset, a job
          # uniqueness conflict) must not be reported as success
          {:error, _reason} ->
            {:error, "That action couldn't be started. Check Tools → Diagnostics for details."}

          _ ->
            {:info, message}
        end

      conn
      |> put_flash(level, flash)
      |> redirect(to: ~p"/sources/#{source}")
    end
  end

  defp media_profiles do
    MediaProfile
    |> order_by(asc: :name)
    |> Repo.all()
  end

  defp default_cookie_behaviour do
    String.to_existing_atom(Settings.get!(:default_cookie_behaviour))
  end

  defp get_onboarding_layout do
    if Settings.get!(:onboarding) do
      {Layouts, :onboarding}
    else
      {Layouts, :app}
    end
  end
end
