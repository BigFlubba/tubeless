defmodule PinchflatWeb.Sources.MediaItemTableLive do
  use PinchflatWeb, :live_view
  use Pinchflat.Media.MediaQuery

  alias Pinchflat.Repo
  alias Pinchflat.Sources
  alias Pinchflat.Media.SkipReason
  alias Pinchflat.Utils.NumberUtils

  @limit 10

  def render(%{total_record_count: 0} = assigns) do
    ~H"""
    <div class="mb-4 flex items-center">
      <.icon_button icon_name="hero-arrow-path" class="h-10 w-10" phx-click="reload_page" />
      <p class="ml-2">Nothing Here!</p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <header class="flex justify-between items-center mb-4">
        <span class="flex items-center">
          <.icon_button icon_name="hero-arrow-path" class="h-10 w-10" phx-click="reload_page" tooltip="Refresh" />
          <span class="mx-2">
            Showing <.localized_number number={length(@records)} /> of <.localized_number number={@filtered_record_count} />
          </span>
        </span>
        <div class="flex items-center gap-2">
          <form :if={@media_state == "other"} id="skip-reason-filter-form" phx-change="filter_reason">
            <select
              name="reason"
              class="rounded-md border-0 bg-meta-4 py-2 pl-3 pr-8 text-sm focus:ring-0 focus:outline-hidden"
            >
              <option value="" selected={is_nil(@reason_filter)}>All reasons</option>
              <option
                :for={reason <- SkipReason.all_reasons()}
                value={reason}
                selected={@reason_filter == reason}
              >
                {SkipReason.label(reason)}
              </option>
            </select>
          </form>
          <div class="bg-meta-4 rounded-md">
            <div class="relative">
              <span class="absolute left-2 top-1/2 -translate-y-1/2 flex">
                <.icon name="hero-magnifying-glass" />
              </span>
              <%!-- The id must be unique because this LiveView renders once per media-state tab --%>
              <form id={"media-search-form-#{@media_state}"} phx-change="search_term" phx-submit="search_term">
                <input
                  type="text"
                  name="q"
                  value={@search_term}
                  placeholder="Search in table..."
                  class="w-full bg-transparent pl-9 pr-4 border-0 focus:ring-0 focus:outline-hidden"
                  phx-debounce="200"
                />
              </form>
            </div>
          </div>
        </div>
      </header>
      <.table rows={@records} table_class="text-white">
        <:col :let={media_item} label="Title" class="max-w-xs">
          <section class="flex items-center space-x-1">
            <.tooltip
              :if={media_item.last_error}
              tooltip={media_item.last_error}
              position="bottom-right"
              tooltip_class="w-64"
            >
              <.icon name="hero-exclamation-circle-solid" class="text-red-500" />
            </.tooltip>
            <span class="truncate">
              <.subtle_link href={~p"/sources/#{@source.id}/media/#{media_item.id}"}>
                {media_item.title}
              </.subtle_link>
            </span>
            <.icon_link
              :if={media_item.original_url}
              href={media_item.original_url}
              target="_blank"
              title="Watch on YouTube"
              icon="hero-arrow-top-right-on-square"
              class="shrink-0"
            />
          </section>
        </:col>
        <:col :let={media_item} :if={@media_state == "other"} label="Status">
          <% status = SkipReason.for_media_item(media_item, @source) %>
          <.tooltip tooltip={status.detail} position="bottom-right" tooltip_class="w-64">
            <span class={["flex items-center gap-1.5", status.class]}>
              <.icon name={status.icon} class="w-5 h-5 shrink-0" />
              <span>{status.label}</span>
            </span>
          </.tooltip>
        </:col>
        <:col :let={media_item} label="Upload Date">
          {DateTime.to_date(media_item.uploaded_at)}
        </:col>
        <:col :let={media_item} :if={@media_state == "downloaded"} label="Downloaded">
          <.relative_datetime :if={media_item.media_downloaded_at} datetime={media_item.media_downloaded_at} />
          <span :if={is_nil(media_item.media_downloaded_at)} class="text-bodydark">—</span>
        </:col>
        <:col :let={media_item} :if={@media_state == "downloaded"} label="Size">
          <.readable_filesize :if={media_item.media_size_bytes} byte_size={media_item.media_size_bytes} />
          <span :if={is_nil(media_item.media_size_bytes)} class="text-bodydark">—</span>
        </:col>
        <:col :let={media_item} label="" class="flex justify-end">
          <.icon_link href={~p"/sources/#{@source.id}/media/#{media_item.id}/edit"} icon="hero-pencil-square" class="mr-4" />
        </:col>
      </.table>
      <section class="flex justify-center mt-5">
        <.live_pagination_controls page_number={@page} total_pages={@total_pages} />
      </section>
    </div>
    """
  end

  def mount(_params, session, socket) do
    PinchflatWeb.Endpoint.subscribe("media_table")

    page = 1
    media_state = session["media_state"]
    # media_profile is needed to explain skip reasons on the "other" (Skipped) tab
    source = Sources.get_source!(session["source_id"]) |> Repo.preload(:media_profile)
    base_query = generate_base_query(source, media_state, nil)
    pagination_attrs = fetch_pagination_attributes(base_query, page, nil)

    new_assigns =
      Map.merge(
        pagination_attrs,
        %{
          base_query: base_query,
          source: source,
          media_state: media_state,
          reason_filter: nil
        }
      )

    {:ok, assign(socket, new_assigns)}
  end

  def handle_event("filter_reason", %{"reason" => reason}, %{assigns: assigns} = socket) do
    reason_filter = parse_reason(reason)
    base_query = generate_base_query(assigns.source, assigns.media_state, reason_filter)
    new_assigns = fetch_pagination_attributes(base_query, 1, assigns.search_term)

    {:noreply, assign(socket, Map.merge(new_assigns, %{base_query: base_query, reason_filter: reason_filter}))}
  end

  def handle_event("page_change", %{"direction" => direction}, %{assigns: assigns} = socket) do
    direction = if direction == "inc", do: 1, else: -1
    new_page = assigns.page + direction
    new_assigns = fetch_pagination_attributes(assigns.base_query, new_page, assigns.search_term)

    {:noreply, assign(socket, new_assigns)}
  end

  def handle_event("search_term", params, socket) do
    search_term = Map.get(params, "q", nil)
    new_assigns = fetch_pagination_attributes(socket.assigns.base_query, 1, search_term)

    {:noreply, assign(socket, new_assigns)}
  end

  # This, along with the handle_info below, is a pattern to reload _all_
  # tables on page rather than just the one that triggered the reload.
  def handle_event("reload_page", _params, socket) do
    PinchflatWeb.Endpoint.broadcast("media_table", "reload", nil)

    {:noreply, socket}
  end

  def handle_info(%{topic: "media_table", event: "reload"}, %{assigns: assigns} = socket) do
    new_assigns = fetch_pagination_attributes(assigns.base_query, assigns.page, assigns.search_term)

    {:noreply, assign(socket, new_assigns)}
  end

  defp fetch_pagination_attributes(base_query, page, ""), do: fetch_pagination_attributes(base_query, page, nil)

  defp fetch_pagination_attributes(base_query, page, nil) do
    total_record_count = Repo.aggregate(base_query, :count, :id)
    total_pages = max(ceil(total_record_count / @limit), 1)
    page = NumberUtils.clamp(page, 1, total_pages)

    records =
      fetch_records(base_query, page)
      |> order_by(desc: :uploaded_at)
      |> Repo.all()

    %{
      page: page,
      total_pages: total_pages,
      records: records,
      search_term: nil,
      total_record_count: total_record_count,
      filtered_record_count: total_record_count
    }
  end

  defp fetch_pagination_attributes(base_query, page, search_term) do
    filtered_base_query = filtered_base_query(base_query, search_term)

    total_record_count = Repo.aggregate(base_query, :count, :id)
    filtered_record_count = Repo.aggregate(filtered_base_query, :count, :id)
    total_pages = max(ceil(filtered_record_count / @limit), 1)
    page = NumberUtils.clamp(page, 1, total_pages)

    records =
      fetch_records(filtered_base_query, page)
      |> order_by(desc: fragment("rank"), desc: :uploaded_at)
      |> Repo.all()

    %{
      page: page,
      total_pages: total_pages,
      records: records,
      search_term: search_term,
      total_record_count: total_record_count,
      filtered_record_count: filtered_record_count
    }
  end

  defp fetch_records(base_query, page) do
    offset = (page - 1) * @limit

    base_query
    |> limit(^@limit)
    |> offset(^offset)
  end

  defp generate_base_query(source, "pending", _reason) do
    MediaQuery.new()
    |> select(^select_fields())
    |> MediaQuery.require_assoc(:media_profile)
    |> where(^dynamic(^MediaQuery.for_source(source) and ^MediaQuery.pending()))
  end

  defp generate_base_query(source, "downloaded", _reason) do
    MediaQuery.new()
    |> select(^select_fields())
    |> where(^dynamic(^MediaQuery.for_source(source) and ^MediaQuery.downloaded()))
  end

  defp generate_base_query(source, "other", reason) do
    MediaQuery.new()
    |> select(^select_fields())
    |> MediaQuery.require_assoc(:media_profile)
    |> where(
      ^dynamic(
        ^MediaQuery.for_source(source) and
          (not (^MediaQuery.downloaded()) and not (^MediaQuery.pending()))
      )
    )
    |> maybe_filter_by_reason(reason)
  end

  defp maybe_filter_by_reason(query, nil), do: query

  defp maybe_filter_by_reason(query, reason) do
    where(query, ^MediaQuery.skip_reason_is(reason))
  end

  defp parse_reason(reason) do
    if reason in Enum.map(SkipReason.all_reasons(), &to_string/1) do
      String.to_existing_atom(reason)
    end
  end

  defp filtered_base_query(base_query, search_term) do
    base_query
    |> MediaQuery.require_assoc(:media_items_search_index)
    |> where(^MediaQuery.matches_search_term(search_term))
  end

  # Selecting only what we need GREATLY speeds up queries on large tables
  defp select_fields do
    [
      :id,
      :title,
      :uploaded_at,
      :prevent_download,
      :last_error,
      :unavailable_at,
      :unavailable_reason,
      :culled_at,
      :original_url,
      :media_downloaded_at,
      :media_size_bytes,
      # Needed by SkipReason to explain why an item is in the Skipped tab
      :short_form_content,
      :livestream,
      :duration_seconds
    ]
  end
end
