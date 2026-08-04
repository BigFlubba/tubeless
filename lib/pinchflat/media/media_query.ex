defmodule Pinchflat.Media.MediaQuery do
  @moduledoc """
  Query helpers for the Media context.

  These methods are made to be one-ish liners used
  to compose queries. Each method should strive to do
  _one_ thing. These don't need to be tested as
  they are just building blocks for other functionality
  which, itself, will be tested.
  """
  import Ecto.Query, warn: false

  alias Pinchflat.Media.MediaItem

  # This allows the module to be aliased and query methods to be used
  # all in one go
  # usage: use Pinchflat.Media.MediaQuery
  defmacro __using__(_opts) do
    quote do
      import Ecto.Query, warn: false

      alias unquote(__MODULE__)
    end
  end

  def new do
    MediaItem
  end

  def for_source(source_id) when is_integer(source_id), do: dynamic([mi], mi.source_id == ^source_id)
  def for_source(source), do: dynamic([mi], mi.source_id == ^source.id)

  def downloaded, do: dynamic([mi], not is_nil(mi.media_filepath))
  def download_prevented, do: dynamic([mi], mi.prevent_download == true)
  def unavailable, do: dynamic([mi], not is_nil(mi.unavailable_at))
  def culling_prevented, do: dynamic([mi], mi.prevent_culling == true)
  def redownloaded, do: dynamic([mi], not is_nil(mi.media_redownloaded_at))
  def upload_date_matches(other_date), do: dynamic([mi], fragment("date(?) = date(?)", mi.uploaded_at, ^other_date))

  def upload_date_after_source_cutoff do
    dynamic(
      [mi, source],
      is_nil(source.download_cutoff_date) or
        fragment("date(?) >= ?", mi.uploaded_at, source.download_cutoff_date)
    )
  end

  def format_matching_profile_preference do
    dynamic(
      [mi, source, media_profile],
      fragment("""
        CASE
          WHEN shorts_behaviour = 'only' AND livestream_behaviour = 'only' THEN
            livestream = true OR short_form_content = true
          WHEN shorts_behaviour = 'only' THEN
            short_form_content = true
          WHEN livestream_behaviour = 'only' THEN
            livestream = true
          WHEN shorts_behaviour = 'exclude' AND livestream_behaviour = 'exclude' THEN
            short_form_content = false AND livestream = false
          WHEN shorts_behaviour = 'exclude' THEN
            short_form_content = false
          WHEN livestream_behaviour = 'exclude' THEN
            livestream = false
          ELSE
            true
        END
      """)
    )
  end

  def matches_source_title_regex do
    dynamic(
      [mi, source],
      is_nil(source.title_filter_regex) or fragment("regexp_like(?, ?)", mi.title, source.title_filter_regex)
    )
  end

  def meets_min_and_max_duration do
    dynamic(
      [mi, source],
      (is_nil(source.min_duration_seconds) or fragment("duration_seconds >= ?", source.min_duration_seconds)) and
        (is_nil(source.max_duration_seconds) or fragment("duration_seconds <= ?", source.max_duration_seconds))
    )
  end

  def past_retention_period do
    dynamic(
      [mi, source],
      fragment("""
        IFNULL(retention_period_days, 0) > 0 AND
        DATETIME(media_downloaded_at, '+' || retention_period_days || ' day') < DATETIME('now')
      """)
    )
  end

  def past_redownload_delay do
    dynamic(
      [mi, source, media_profile],
      # Returns media items where the uploaded_at is at least redownload_delay_days ago AND
      # downloaded_at minus the redownload_delay_days is before the upload date
      fragment("""
        IFNULL(redownload_delay_days, 0) > 0 AND
        DATE('now', '-' || redownload_delay_days || ' day') > DATE(uploaded_at) AND
        DATE(media_downloaded_at, '-' || redownload_delay_days || ' day') < DATE(uploaded_at)
      """)
    )
  end

  def cullable do
    dynamic(
      [mi, source],
      ^downloaded() and
        ^past_retention_period() and
        not (^culling_prevented())
    )
  end

  def deletable_based_on_source_cutoff do
    dynamic(
      [mi, source],
      ^downloaded() and
        not (^upload_date_after_source_cutoff()) and
        not (^culling_prevented())
    )
  end

  def pending do
    dynamic(
      [mi],
      not (^downloaded()) and
        not (^download_prevented()) and
        ^upload_date_after_source_cutoff() and
        ^format_matching_profile_preference() and
        ^matches_source_title_regex() and
        ^meets_min_and_max_duration()
    )
  end

  # True when the media item has a non-terminal (available/scheduled/executing/retryable)
  # MediaDownloadWorker job attached via a Task - i.e. a download is actually queued or
  # in flight for it. `pending/0` is only an eligibility predicate and says nothing about
  # whether a job exists, so this is what separates "queued for download" from
  # "eligible but nothing scheduled yet". Kept as a self-contained EXISTS so it composes
  # into `pending/0`-based queries without forcing an outer join.
  def in_download_queue do
    dynamic(
      [mi],
      fragment(
        """
        EXISTS (
          SELECT 1 FROM tasks t
          INNER JOIN oban_jobs j ON j.id = t.job_id
          WHERE t.media_item_id = ?
            AND j.worker LIKE '%.MediaDownloadWorker'
            AND j.state IN ('available', 'scheduled', 'executing', 'retryable')
        )
        """,
        mi.id
      )
    )
  end

  # True when the media item has a MediaDownloadWorker job currently `executing` - i.e.
  # yt-dlp is actively downloading it right now, not merely waiting in the queue. This is
  # a strict subset of `in_download_queue/0` (which also counts available/scheduled/retryable),
  # so callers that want "queued but not yet started" compose `in_download_queue and not downloading`.
  def downloading do
    dynamic(
      [mi],
      fragment(
        """
        EXISTS (
          SELECT 1 FROM tasks t
          INNER JOIN oban_jobs j ON j.id = t.job_id
          WHERE t.media_item_id = ?
            AND j.worker LIKE '%.MediaDownloadWorker'
            AND j.state = 'executing'
        )
        """,
        mi.id
      )
    )
  end

  def upgradeable do
    dynamic(
      [mi, source],
      ^downloaded() and
        not (^download_prevented()) and
        not (^redownloaded()) and
        ^past_redownload_delay()
    )
  end

  # ---- Skip-reason filtering (Skipped tab) ----
  #
  # These mirror the precedence in `Pinchflat.Media.SkipReason.reason/2` exactly so the
  # reason filter dropdown and the per-row chip can never disagree. Each clause reads as
  # "fails this reason's predicate AND passes every higher-precedence one", so the clauses
  # are mutually exclusive. They assume the query has the source + media_profile bindings
  # joined (the Skipped tab query does via `require_assoc(:media_profile)`).
  def skip_reason_is(:unavailable), do: dynamic([mi], not is_nil(mi.unavailable_at))

  def skip_reason_is(:removed) do
    dynamic([mi], is_nil(mi.unavailable_at) and not is_nil(mi.culled_at))
  end

  def skip_reason_is(:ignored) do
    dynamic([mi], is_nil(mi.unavailable_at) and is_nil(mi.culled_at) and mi.prevent_download == true)
  end

  def skip_reason_is(:before_cutoff) do
    dynamic([mi], ^skip_reason_plain() and not (^upload_date_after_source_cutoff()))
  end

  def skip_reason_is(:format_excluded) do
    dynamic(
      [mi],
      ^skip_reason_plain() and ^upload_date_after_source_cutoff() and not (^format_matching_profile_preference())
    )
  end

  def skip_reason_is(:title_filter) do
    dynamic(
      [mi],
      ^skip_reason_plain() and ^upload_date_after_source_cutoff() and
        ^format_matching_profile_preference() and not (^matches_source_title_regex())
    )
  end

  def skip_reason_is(:too_short) do
    dynamic([mi], ^skip_reason_pre_duration() and ^below_min_duration())
  end

  def skip_reason_is(:too_long) do
    dynamic([mi], ^skip_reason_pre_duration() and ^at_least_min_duration() and ^above_max_duration())
  end

  def skip_reason_is(:filtered) do
    dynamic([mi], ^skip_reason_pre_duration() and not (^below_min_duration()) and not (^above_max_duration()))
  end

  # An item that isn't unavailable, retention-culled, or manually ignored - i.e. one
  # excluded purely by the source's filter rules.
  defp skip_reason_plain do
    dynamic([mi], is_nil(mi.unavailable_at) and is_nil(mi.culled_at) and mi.prevent_download == false)
  end

  # Passed every filter predicate up to (but not including) the duration checks.
  defp skip_reason_pre_duration do
    dynamic(
      [mi],
      ^skip_reason_plain() and ^upload_date_after_source_cutoff() and
        ^format_matching_profile_preference() and ^matches_source_title_regex()
    )
  end

  # A NULL `duration_seconds` is neither too short nor too long — matching
  # `SkipReason.too_short?/2`/`too_long?/2`, which return false for a nil duration.
  # The `is_nil` guards are what keep these predicates *false* rather than NULL in
  # that case: a NULL would make the negations in `:filtered` NULL too, and an item
  # with no duration would then match no reason filter at all while its row chip
  # said "Filtered".
  defp below_min_duration do
    dynamic(
      [mi, source],
      not is_nil(source.min_duration_seconds) and not is_nil(mi.duration_seconds) and
        mi.duration_seconds < source.min_duration_seconds
    )
  end

  defp above_max_duration do
    dynamic(
      [mi, source],
      not is_nil(source.max_duration_seconds) and not is_nil(mi.duration_seconds) and
        mi.duration_seconds > source.max_duration_seconds
    )
  end

  defp at_least_min_duration do
    dynamic(
      [mi, source],
      is_nil(source.min_duration_seconds) or is_nil(mi.duration_seconds) or
        mi.duration_seconds >= source.min_duration_seconds
    )
  end

  def matches_search_term(nil), do: dynamic([mi], true)

  def matches_search_term(term) do
    escaped_term = clean_search_term(term)

    # Matching on `term` instead of `escaped_term` because the latter can mangle empty strings
    case String.trim(term) do
      "" -> dynamic([mi], true)
      _ -> dynamic([mi], fragment("media_items_search_index MATCH ?", ^escaped_term))
    end
  end

  def require_assoc(query, identifier) do
    if has_named_binding?(query, identifier) do
      query
    else
      do_require_assoc(query, identifier)
    end
  end

  defp do_require_assoc(query, :media_items_search_index) do
    from(mi in query, join: s in assoc(mi, :media_items_search_index), as: :media_items_search_index)
  end

  defp do_require_assoc(query, :source) do
    from(mi in query, join: s in assoc(mi, :source), as: :source)
  end

  defp do_require_assoc(query, :media_profile) do
    query
    |> require_assoc(:source)
    |> join(:inner, [mi, source], mp in assoc(source, :media_profile), as: :media_profile)
  end

  # This needs to be a non-dynamic query because it alone should control things like
  # ordering and `snippets` for full-text search
  def matching_search_term(query, nil), do: query

  def matching_search_term(query, term) do
    escaped_term = clean_search_term(term)

    from(mi in query,
      join: mi_search_index in assoc(mi, :media_items_search_index),
      where: fragment("media_items_search_index MATCH ?", ^escaped_term),
      select_merge: %{
        matching_search_term:
          fragment("""
            coalesce(snippet(media_items_search_index, 0, '[PF_HIGHLIGHT]', '[/PF_HIGHLIGHT]', '...', 20), '') ||
            ' ' ||
            coalesce(snippet(media_items_search_index, 1, '[PF_HIGHLIGHT]', '[/PF_HIGHLIGHT]', '...', 20), '')
          """)
      },
      order_by: [desc: fragment("rank")]
    )
  end

  # SQLite's FTS5 is very picky about what it will accept as a search term.
  # To that end, we need to clean up the search term before passing it to the
  # MATCH clause.
  # This method:
  #   - Trims leading and trailing whitespace
  #   - Collapses multiple spaces into a single space
  #   - Removes quote characters
  #   - Wraps any word in quotes (must happen after the double quote replacement)
  #
  # This allows for works with apostrophes and quotes to be searched for correctly
  defp clean_search_term(""), do: ""

  defp clean_search_term(term) do
    term
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
    |> String.split(~r/\s+/)
    |> Enum.map(fn str -> String.replace(str, ~s("), "") end)
    |> Enum.map_join(" ", fn str -> ~s("#{str}") end)
  end
end
