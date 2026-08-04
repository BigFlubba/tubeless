defmodule Pinchflat.Media.SkipReason do
  @moduledoc """
  Explains _why_ a media item is in the "Skipped" tab (neither downloaded nor
  pending/queued). This is a pure function - it re-evaluates the exact same
  predicates the `Pinchflat.Media.MediaQuery.pending/0` query uses, but decomposed
  so each excluded item can name the single condition that disqualified it.

  This module is the spec for skip reasons. The reason-filter dropdown on the
  Skipped tab is backed by `MediaQuery.skip_reason_is/1`, whose clauses mirror the
  precedence here one-for-one so the filter and the per-row chip can never disagree.

  The precedence matters: an item can fail several predicates at once (a members-only
  Short that's also too long), so the reasons are checked in a fixed order and the
  first match wins.
  """

  alias Pinchflat.Media.MediaItem
  alias Pinchflat.Sources.Source

  @doc """
  Returns a presentation map describing why `media_item` was skipped:

      %{reason: atom(), label: String.t(), icon: String.t(), class: String.t(), detail: String.t()}

  `reason` is one of: `:unavailable`, `:removed`, `:ignored`, `:before_cutoff`,
  `:format_excluded`, `:title_filter`, `:too_short`, `:too_long`, `:filtered`.

  `source.media_profile` must be preloaded.
  """
  def for_media_item(%MediaItem{} = media_item, %Source{} = source) do
    reason = reason(media_item, source)
    present(reason, media_item, source)
  end

  @doc "Returns just the reason atom. See `for_media_item/2` for the possible values."
  def reason(%MediaItem{} = media_item, %Source{} = source) do
    cond do
      not is_nil(media_item.unavailable_at) -> :unavailable
      not is_nil(media_item.culled_at) -> :removed
      media_item.prevent_download -> :ignored
      before_cutoff?(media_item, source) -> :before_cutoff
      not format_matches?(media_item, source) -> :format_excluded
      not title_matches?(media_item, source) -> :title_filter
      too_short?(media_item, source) -> :too_short
      too_long?(media_item, source) -> :too_long
      true -> :filtered
    end
  end

  @doc "The ordered list of every reason, for building filter dropdowns."
  def all_reasons do
    ~w(unavailable removed ignored before_cutoff format_excluded title_filter too_short too_long filtered)a
  end

  @doc "The human label for a reason atom (for filter dropdown options)."
  def label(reason), do: presentation(reason).label

  # ---- predicate helpers (mirror MediaQuery) ----

  defp before_cutoff?(_media_item, %Source{download_cutoff_date: nil}), do: false

  defp before_cutoff?(%MediaItem{uploaded_at: nil}, _source), do: false

  defp before_cutoff?(%MediaItem{uploaded_at: uploaded_at}, %Source{download_cutoff_date: cutoff}) do
    Date.compare(DateTime.to_date(uploaded_at), cutoff) == :lt
  end

  defp format_matches?(media_item, source) do
    profile = source.media_profile
    short = media_item.short_form_content
    live = media_item.livestream

    case {profile.shorts_behaviour, profile.livestream_behaviour} do
      {:only, :only} -> live or short
      {:only, _} -> short
      {_, :only} -> live
      {:exclude, :exclude} -> not short and not live
      {:exclude, _} -> not short
      {_, :exclude} -> not live
      _ -> true
    end
  end

  defp title_matches?(_media_item, %Source{title_filter_regex: nil}), do: true

  defp title_matches?(%MediaItem{title: title}, %Source{title_filter_regex: regex}) do
    case Regex.compile(regex) do
      {:ok, compiled} -> Regex.match?(compiled, title || "")
      # A stored regex is validated on save, so this is defensive - treat an
      # uncompilable pattern as "not the reason it was skipped".
      _ -> true
    end
  end

  defp too_short?(%MediaItem{duration_seconds: nil}, _source), do: false
  defp too_short?(_media_item, %Source{min_duration_seconds: nil}), do: false

  defp too_short?(%MediaItem{duration_seconds: duration}, %Source{min_duration_seconds: min}) do
    duration < min
  end

  defp too_long?(%MediaItem{duration_seconds: nil}, _source), do: false
  defp too_long?(_media_item, %Source{max_duration_seconds: nil}), do: false

  defp too_long?(%MediaItem{duration_seconds: duration}, %Source{max_duration_seconds: max}) do
    duration > max
  end

  # ---- presentation ----

  defp present(reason, media_item, source) do
    presentation(reason)
    |> Map.put(:reason, reason)
    |> Map.put(:detail, detail(reason, media_item, source))
  end

  defp presentation(:unavailable),
    do: %{label: "Unavailable", icon: "hero-no-symbol", class: "text-amber-400"}

  defp presentation(:removed), do: %{label: "Removed", icon: "hero-trash", class: "text-slate-300"}
  defp presentation(:ignored), do: %{label: "Ignored", icon: "hero-eye-slash", class: "text-slate-300"}

  defp presentation(:before_cutoff),
    do: %{label: "Before cutoff", icon: "hero-calendar", class: "text-slate-300"}

  defp presentation(:format_excluded),
    do: %{label: "Wrong format", icon: "hero-film", class: "text-slate-300"}

  defp presentation(:title_filter),
    do: %{label: "Title filtered", icon: "hero-funnel", class: "text-slate-300"}

  defp presentation(:too_short), do: %{label: "Too short", icon: "hero-clock", class: "text-slate-300"}
  defp presentation(:too_long), do: %{label: "Too long", icon: "hero-clock", class: "text-slate-300"}
  defp presentation(:filtered), do: %{label: "Filtered out", icon: "hero-funnel", class: "text-slate-300"}

  # ---- concrete "why" detail ----

  defp detail(:unavailable, %MediaItem{unavailable_reason: reason}, _source) when is_binary(reason) do
    "Skipped: #{reason}"
  end

  defp detail(:unavailable, _media_item, _source) do
    "Skipped: members-only, private, or removed"
  end

  defp detail(:removed, %MediaItem{prevent_download: true}, _source) do
    "Downloaded, then deleted after its retention period. It won't be re-downloaded"
  end

  defp detail(:removed, _media_item, _source) do
    "Downloaded, then deleted because it's before the source's cutoff date. It may be re-downloaded if the cutoff changes"
  end

  defp detail(:ignored, _media_item, _source), do: "Manually marked to not download"

  defp detail(:before_cutoff, %MediaItem{uploaded_at: uploaded_at}, %Source{download_cutoff_date: cutoff}) do
    "Uploaded #{DateTime.to_date(uploaded_at)}, before this source's cutoff of #{cutoff}"
  end

  defp detail(:format_excluded, media_item, source) do
    profile = source.media_profile

    cond do
      media_item.short_form_content && profile.shorts_behaviour == :exclude ->
        "Excluded because it's a Short and this profile excludes Shorts"

      media_item.livestream && profile.livestream_behaviour == :exclude ->
        "Excluded because it's a livestream and this profile excludes livestreams"

      profile.shorts_behaviour == :only && not media_item.short_form_content ->
        "Excluded because this profile only downloads Shorts"

      profile.livestream_behaviour == :only && not media_item.livestream ->
        "Excluded because this profile only downloads livestreams"

      true ->
        "Excluded by this profile's Shorts and livestream rules"
    end
  end

  defp detail(:title_filter, _media_item, %Source{title_filter_regex: regex}) do
    "Title doesn't match this source's filter: /#{regex}/"
  end

  defp detail(:too_short, %MediaItem{duration_seconds: duration}, %Source{min_duration_seconds: min}) do
    "#{format_duration(duration)} is under the #{format_duration(min)} minimum"
  end

  defp detail(:too_long, %MediaItem{duration_seconds: duration}, %Source{max_duration_seconds: max}) do
    "#{format_duration(duration)} is over the #{format_duration(max)} maximum"
  end

  defp detail(:filtered, _media_item, _source) do
    "Excluded by this source's profile rules (duration, format, title, or cutoff date)"
  end

  defp format_duration(nil), do: "unknown"

  defp format_duration(seconds) when is_integer(seconds) do
    hours = div(seconds, 3600)
    minutes = seconds |> rem(3600) |> div(60)
    secs = rem(seconds, 60)

    if hours > 0 do
      "#{hours}:#{pad(minutes)}:#{pad(secs)}"
    else
      "#{minutes}:#{pad(secs)}"
    end
  end

  defp pad(number), do: String.pad_leading(to_string(number), 2, "0")
end
