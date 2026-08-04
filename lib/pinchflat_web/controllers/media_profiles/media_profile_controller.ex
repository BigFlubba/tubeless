defmodule PinchflatWeb.MediaProfiles.MediaProfileController do
  use PinchflatWeb, :controller
  use Pinchflat.Sources.SourcesQuery
  use Pinchflat.Profiles.ProfilesQuery
  use Pinchflat.Media.MediaQuery

  alias Pinchflat.Repo
  alias Pinchflat.Sources
  alias Pinchflat.Profiles
  alias Pinchflat.Sources.Source
  alias Pinchflat.Media.MediaItem
  alias Pinchflat.Reconciliation
  alias Pinchflat.Profiles.MediaProfile
  alias Pinchflat.Profiles.MediaProfileDeletionWorker

  def index(conn, _params) do
    render(conn, :index)
  end

  def new(conn, params) do
    # Preload an existing media profile for faster creation
    %MediaProfile{} =
      cs_struct =
      case to_string(params["template_id"]) do
        "" -> %MediaProfile{}
        template_id -> Repo.get(MediaProfile, template_id) || %MediaProfile{}
      end

    render(conn, :new,
      layout: get_onboarding_layout(),
      changeset:
        Profiles.change_media_profile(%MediaProfile{
          cs_struct
          | id: nil,
            name: nil,
            marked_for_deletion_at: nil
        })
    )
  end

  def create(conn, %{"media_profile" => media_profile_params}) do
    case Profiles.create_media_profile(media_profile_params) do
      {:ok, media_profile} ->
        redirect_location =
          if Settings.get!(:onboarding), do: ~p"/?onboarding=1", else: ~p"/media_profiles/#{media_profile}"

        conn
        |> put_flash(:info, "Media profile created successfully.")
        |> redirect(to: redirect_location)

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset, layout: get_onboarding_layout())
    end
  end

  def show(conn, %{"id" => id}) do
    media_profile = Profiles.get_media_profile!(id)
    sources = sources_with_totals(media_profile)

    render(conn, :show,
      media_profile: media_profile,
      sources: sources,
      failing_source_ids: Sources.failing_source_ids(Enum.map(sources, & &1.id)),
      profile_totals: profile_totals(sources)
    )
  end

  # The sources using this profile, each carrying its downloaded count and byte
  # total. One LEFT JOIN over a grouped subquery rather than a count per row, so
  # a profile with dozens of sources still costs one query.
  #
  # The subquery is scoped to THIS profile's sources rather than grouping every
  # downloaded item in the database: the outer `media_profile_id` filter can't
  # constrain a grouped subquery, so without the inner join, opening any one
  # profile would materialize an aggregate over the whole library.
  defp sources_with_totals(media_profile) do
    downloaded_subquery =
      from(m in MediaItem,
        inner_join: s in assoc(m, :source),
        select: %{
          source_id: m.source_id,
          downloaded_count: count(m.id),
          media_size_bytes: sum(m.media_size_bytes)
        },
        where: s.media_profile_id == ^media_profile.id,
        where: is_nil(s.marked_for_deletion_at),
        where: ^MediaQuery.downloaded(),
        group_by: m.source_id
      )

    SourcesQuery.new()
    |> join(:left, [s], d in subquery(downloaded_subquery), on: d.source_id == s.id)
    |> where(^SourcesQuery.for_media_profile(media_profile))
    # Matches the profiles index, which counts only sources that aren't being deleted
    |> where([s], is_nil(s.marked_for_deletion_at))
    |> order_by([s], asc: fragment("? COLLATE NOCASE", s.custom_name))
    |> select([s], map(s, ^Source.__schema__(:fields)))
    |> select_merge([s, d], %{
      downloaded_count: coalesce(d.downloaded_count, 0),
      media_size_bytes: coalesce(d.media_size_bytes, 0)
    })
    |> Repo.all()
  end

  # Rolled up in Elixir from the already-loaded rows — the header strip needs no
  # query of its own
  defp profile_totals(sources) do
    %{
      source_count: length(sources),
      downloaded_count: Enum.sum(Enum.map(sources, & &1.downloaded_count)),
      media_size_bytes: Enum.sum(Enum.map(sources, & &1.media_size_bytes))
    }
  end

  def edit(conn, %{"id" => id}) do
    media_profile = Profiles.get_media_profile!(id)
    changeset = Profiles.change_media_profile(media_profile)

    render(conn, :edit, media_profile: media_profile, changeset: changeset)
  end

  def update(conn, %{"id" => id, "media_profile" => media_profile_params}) do
    media_profile = Profiles.get_media_profile!(id)

    case Profiles.update_media_profile(media_profile, media_profile_params) do
      {:ok, media_profile} ->
        # Profile changes can alter predicted paths, invalidating any staged reconcile plan
        Reconciliation.mark_ready_plans_stale()

        conn
        |> put_flash(:info, "Media profile updated successfully.")
        |> redirect(to: ~p"/media_profiles/#{media_profile}")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit, media_profile: media_profile, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id} = params) do
    # This awkward comparison converts the string to a boolean
    delete_files = Map.get(params, "delete_files", "") == "true"
    media_profile = Profiles.get_media_profile!(id)

    {:ok, _} = Profiles.update_media_profile(media_profile, %{marked_for_deletion_at: DateTime.utc_now()})
    MediaProfileDeletionWorker.kickoff(media_profile, %{delete_files: delete_files})

    conn
    |> put_flash(:info, "Media Profile deletion started. This may take a while to complete.")
    |> redirect(to: ~p"/media_profiles")
  end

  defp get_onboarding_layout do
    if Settings.get!(:onboarding) do
      {Layouts, :onboarding}
    else
      {Layouts, :app}
    end
  end
end
