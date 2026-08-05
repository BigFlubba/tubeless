defmodule PinchflatWeb.Sources.SourceLive.IndexTableLive do
  use PinchflatWeb, :live_view
  use Pinchflat.Media.MediaQuery
  use Pinchflat.Sources.SourcesQuery

  import PinchflatWeb.Helpers.SortingHelpers
  import PinchflatWeb.Helpers.PaginationHelpers

  alias Pinchflat.Repo
  alias Pinchflat.Sources.Source
  alias Pinchflat.Media.MediaItem

  @per_page_options [10, 25, 50]

  def mount(_params, session, socket) do
    limit = session["results_per_page"]

    initial_params =
      Map.merge(
        %{
          sort_key: session["initial_sort_key"],
          sort_direction: session["initial_sort_direction"],
          per_page: limit,
          profile_filter: nil,
          profile_options: profile_filter_options()
        },
        get_pagination_attributes(sources_query(nil), 1, limit)
      )

    socket
    |> assign(initial_params)
    |> set_sources()
    |> then(&{:ok, &1})
  end

  def handle_event("page_change", %{"direction" => direction}, %{assigns: assigns} = socket) do
    new_page = update_page_number(assigns.page, direction, assigns.total_pages)

    socket
    |> assign(get_pagination_attributes(sources_query(assigns.profile_filter), new_page, assigns.limit))
    |> set_sources()
    |> then(&{:noreply, &1})
  end

  def handle_event("sort_update", %{"sort_key" => sort_key}, %{assigns: assigns} = socket) do
    new_sort_key = String.to_existing_atom(sort_key)

    new_params = %{
      sort_key: new_sort_key,
      sort_direction: get_sort_direction(assigns.sort_key, new_sort_key, assigns.sort_direction)
    }

    socket
    |> assign(new_params)
    |> set_sources()
    |> then(&{:noreply, &1})
  end

  def handle_event("per_page_change", %{"per_page" => per_page}, %{assigns: assigns} = socket) do
    query = sources_query(assigns.profile_filter)
    records_per_page = resolve_per_page(per_page, query)

    socket
    |> assign(:per_page, per_page)
    |> assign(get_pagination_attributes(query, 1, records_per_page))
    |> set_sources()
    |> then(&{:noreply, &1})
  end

  def handle_event("profile_filter_change", %{"profile_filter" => raw_filter}, %{assigns: assigns} = socket) do
    profile_filter = parse_profile_filter(raw_filter)
    query = sources_query(profile_filter)
    records_per_page = resolve_per_page(assigns.per_page, query)

    socket
    |> assign(:profile_filter, profile_filter)
    |> assign(get_pagination_attributes(query, 1, records_per_page))
    |> set_sources()
    |> then(&{:noreply, &1})
  end

  defp resolve_per_page("all", query), do: max(Repo.aggregate(query, :count, :id), 1)
  defp resolve_per_page(per_page, _query) when is_integer(per_page), do: per_page
  defp resolve_per_page(per_page, _query), do: String.to_integer(per_page)

  defp parse_profile_filter(""), do: nil
  defp parse_profile_filter(id), do: String.to_integer(id)

  defp per_page_select_options do
    Enum.map(@per_page_options, &{&1, &1}) ++ [{"All", "all"}]
  end

  defp profile_filter_options do
    from(s in Source,
      inner_join: mp in assoc(s, :media_profile),
      where: is_nil(s.marked_for_deletion_at) and is_nil(mp.marked_for_deletion_at),
      distinct: true,
      order_by: [asc: fragment("? COLLATE NOCASE", mp.name)],
      select: {mp.name, mp.id}
    )
    |> Repo.all()
  end

  defp sort_attr(:pending_count), do: dynamic([s, mp, dl, pe], pe.pending_count)
  defp sort_attr(:downloaded_count), do: dynamic([s, mp, dl], dl.downloaded_count)
  defp sort_attr(:media_size_bytes), do: dynamic([s, mp, dl], dl.media_size_bytes)
  defp sort_attr(:media_profile_name), do: dynamic([s, mp], fragment("? COLLATE NOCASE", mp.name))
  defp sort_attr(:custom_name), do: dynamic([s], fragment("? COLLATE NOCASE", s.custom_name))
  defp sort_attr(:enabled), do: dynamic([s], s.enabled)
  defp sort_attr(:collection_type), do: dynamic([s], s.collection_type)

  defp set_sources(%{assigns: assigns} = socket) do
    sources =
      sources_query(assigns.profile_filter)
      |> order_by(^[{assigns.sort_direction, sort_attr(assigns.sort_key)}, asc: :id])
      |> limit(^assigns.limit)
      |> offset(^assigns.offset)
      |> Repo.all()

    assign(socket, %{sources: sources})
  end

  defp sources_query(profile_filter) do
    downloaded_subquery =
      from(
        m in MediaItem,
        select: %{downloaded_count: count(m.id), source_id: m.source_id, media_size_bytes: sum(m.media_size_bytes)},
        where: ^MediaQuery.downloaded(),
        group_by: m.source_id
      )

    pending_subquery =
      from(
        m in MediaItem,
        inner_join: s in assoc(m, :source),
        inner_join: mp in assoc(s, :media_profile),
        select: %{pending_count: count(m.id), source_id: m.source_id},
        where: ^MediaQuery.pending(),
        group_by: m.source_id
      )

    from(s in Source,
      as: :source,
      inner_join: mp in assoc(s, :media_profile),
      left_join: d in subquery(downloaded_subquery),
      on: d.source_id == s.id,
      left_join: p in subquery(pending_subquery),
      on: p.source_id == s.id,
      where: is_nil(s.marked_for_deletion_at) and is_nil(mp.marked_for_deletion_at),
      preload: [media_profile: mp],
      select: map(s, ^Source.__schema__(:fields)),
      select_merge: %{
        downloaded_count: coalesce(d.downloaded_count, 0),
        pending_count: coalesce(p.pending_count, 0),
        media_size_bytes: coalesce(d.media_size_bytes, 0)
      }
    )
    |> maybe_filter_by_profile(profile_filter)
  end

  defp maybe_filter_by_profile(query, nil), do: query

  defp maybe_filter_by_profile(query, profile_id) do
    from([s, mp] in query, where: mp.id == ^profile_id)
  end
end
