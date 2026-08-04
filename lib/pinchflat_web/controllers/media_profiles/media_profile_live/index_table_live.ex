defmodule PinchflatWeb.MediaProfiles.MediaProfileLive.IndexTableLive do
  use PinchflatWeb, :live_view
  use Pinchflat.Media.MediaQuery

  import PinchflatWeb.Helpers.SortingHelpers
  import PinchflatWeb.Helpers.PaginationHelpers

  import PinchflatWeb.MediaProfiles.MediaProfileSummary,
    only: [resolution_label: 1, container_label: 1, content_label: 1, extras_labels: 1]

  alias Pinchflat.Repo
  alias Pinchflat.Media.MediaItem
  alias Pinchflat.Sources.Source
  alias Pinchflat.Profiles.MediaProfile

  @sortable_keys ~w(name preferred_resolution podcast_enabled source_count downloaded_count media_size_bytes)a

  def mount(_params, session, socket) do
    limit = session["results_per_page"]

    initial_params =
      Map.merge(
        %{
          sort_key: session["initial_sort_key"],
          sort_direction: session["initial_sort_direction"]
        },
        get_pagination_attributes(pagination_query(), 1, limit)
      )

    socket
    |> assign(initial_params)
    |> set_media_profiles()
    |> then(&{:ok, &1})
  end

  def handle_event("page_change", %{"direction" => direction}, %{assigns: assigns} = socket) do
    new_page = update_page_number(assigns.page, direction, assigns.total_pages)

    socket
    |> assign(get_pagination_attributes(pagination_query(), new_page, assigns.limit))
    |> set_media_profiles()
    |> then(&{:noreply, &1})
  end

  def handle_event("sort_update", %{"sort_key" => sort_key}, %{assigns: assigns} = socket) do
    # Resolving against the known-sortable list (rather than String.to_existing_atom
    # + a sort_attr/1 clause) means a hand-crafted payload is ignored instead of
    # crashing the LiveView
    case Enum.find(@sortable_keys, &(to_string(&1) == sort_key)) do
      nil ->
        {:noreply, socket}

      new_sort_key ->
        new_params = %{
          sort_key: new_sort_key,
          sort_direction: get_sort_direction(assigns.sort_key, new_sort_key, assigns.sort_direction)
        }

        socket
        |> assign(new_params)
        |> set_media_profiles()
        |> then(&{:noreply, &1})
    end
  end

  defp sort_attr(:source_count), do: dynamic([mp, s], s.source_count)
  defp sort_attr(:downloaded_count), do: dynamic([mp, s, d], d.downloaded_count)
  defp sort_attr(:media_size_bytes), do: dynamic([mp, s, d], d.media_size_bytes)
  defp sort_attr(:podcast_enabled), do: dynamic([mp], mp.podcast_enabled)
  defp sort_attr(:name), do: dynamic([mp], fragment("? COLLATE NOCASE", mp.name))

  defp sort_attr(:preferred_resolution) do
    dynamic(
      [mp],
      fragment(
        """
        CASE ?
          WHEN '4320p' THEN 0
          WHEN '2160p' THEN 1
          WHEN '1440p' THEN 2
          WHEN '1080p' THEN 3
          WHEN '720p' THEN 4
          WHEN '480p' THEN 5
          WHEN '360p' THEN 6
          ELSE 7
        END
        """,
        mp.preferred_resolution
      )
    )
  end

  defp set_media_profiles(%{assigns: assigns} = socket) do
    media_profiles =
      media_profiles_query()
      |> order_by(^[{assigns.sort_direction, sort_attr(assigns.sort_key)}, asc: :id])
      |> limit(^assigns.limit)
      |> offset(^assigns.offset)
      |> Repo.all()

    assign(socket, %{media_profiles: media_profiles})
  end

  # Counting rows for pagination needs no aggregates, and `Repo.aggregate/3` only
  # swaps the select - it keeps the joins, so counting through `media_profiles_query/0`
  # would materialize both grouped subqueries (a full pass over media_items) on
  # every mount and page change. Same `where`, so the count always matches the rows
  defp pagination_query do
    from(mp in MediaProfile, where: is_nil(mp.marked_for_deletion_at))
  end

  defp media_profiles_query do
    source_subquery =
      from(
        s in Source,
        select: %{media_profile_id: s.media_profile_id, source_count: count(s.id)},
        where: is_nil(s.marked_for_deletion_at),
        group_by: s.media_profile_id
      )

    downloaded_subquery =
      from(
        m in MediaItem,
        inner_join: s in assoc(m, :source),
        select: %{
          media_profile_id: s.media_profile_id,
          downloaded_count: count(m.id),
          media_size_bytes: sum(m.media_size_bytes)
        },
        where: ^MediaQuery.downloaded(),
        where: is_nil(s.marked_for_deletion_at),
        group_by: s.media_profile_id
      )

    from(mp in MediaProfile,
      as: :media_profile,
      left_join: s in subquery(source_subquery),
      on: s.media_profile_id == mp.id,
      left_join: d in subquery(downloaded_subquery),
      on: d.media_profile_id == mp.id,
      where: is_nil(mp.marked_for_deletion_at),
      select: map(mp, ^MediaProfile.__schema__(:fields)),
      select_merge: %{
        source_count: coalesce(s.source_count, 0),
        downloaded_count: coalesce(d.downloaded_count, 0),
        media_size_bytes: coalesce(d.media_size_bytes, 0)
      }
    )
  end
end
