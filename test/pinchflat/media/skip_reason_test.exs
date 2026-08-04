defmodule Pinchflat.Media.SkipReasonTest do
  use Pinchflat.DataCase

  import Pinchflat.MediaFixtures
  import Pinchflat.SourcesFixtures
  import Pinchflat.ProfilesFixtures

  alias Pinchflat.Repo
  alias Pinchflat.Media.SkipReason

  # Builds a source (with its media_profile preloaded) plus a media item, so
  # SkipReason can be exercised as the pure function it is.
  defp build(source_attrs, item_attrs) do
    {profile_attrs, source_attrs} = Map.pop(source_attrs, :profile, %{})
    profile = media_profile_fixture(profile_attrs)
    source = source_fixture(Map.put(source_attrs, :media_profile_id, profile.id)) |> Repo.preload(:media_profile)
    item = media_item_fixture(Map.merge(%{source_id: source.id, media_filepath: nil}, item_attrs))
    {source, item}
  end

  describe "reason/2" do
    test "returns :unavailable when the item is marked unavailable" do
      {source, item} = build(%{}, %{unavailable_at: DateTime.utc_now(), unavailable_reason: "members-only"})

      assert SkipReason.reason(item, source) == :unavailable
    end

    test "returns :removed when the item was culled" do
      {source, item} = build(%{}, %{culled_at: DateTime.utc_now()})

      assert SkipReason.reason(item, source) == :removed
    end

    test "prefers :unavailable over :removed" do
      {source, item} = build(%{}, %{unavailable_at: DateTime.utc_now(), culled_at: DateTime.utc_now()})

      assert SkipReason.reason(item, source) == :unavailable
    end

    test "returns :ignored when download is manually prevented" do
      {source, item} = build(%{}, %{prevent_download: true})

      assert SkipReason.reason(item, source) == :ignored
    end

    test "returns :before_cutoff when uploaded before the download cutoff" do
      {source, item} =
        build(
          %{download_cutoff_date: ~D[2023-01-01]},
          %{uploaded_at: ~U[2022-06-01 00:00:00Z]}
        )

      assert SkipReason.reason(item, source) == :before_cutoff
    end

    test "returns :format_excluded for a Short when the profile excludes Shorts" do
      {source, item} = build(%{profile: %{shorts_behaviour: :exclude}}, %{short_form_content: true})

      assert SkipReason.reason(item, source) == :format_excluded
    end

    test "returns :format_excluded for a regular video when the profile only wants Shorts" do
      {source, item} = build(%{profile: %{shorts_behaviour: :only}}, %{short_form_content: false, livestream: false})

      assert SkipReason.reason(item, source) == :format_excluded
    end

    test "returns :title_filter when the title doesn't match the source regex" do
      {source, item} = build(%{title_filter_regex: "MATCHME"}, %{title: "totally different"})

      assert SkipReason.reason(item, source) == :title_filter
    end

    test "returns :too_short when under the minimum duration" do
      {source, item} = build(%{min_duration_seconds: 600}, %{duration_seconds: 120})

      assert SkipReason.reason(item, source) == :too_short
    end

    test "returns :too_long when over the maximum duration" do
      {source, item} = build(%{max_duration_seconds: 600}, %{duration_seconds: 1200})

      assert SkipReason.reason(item, source) == :too_long
    end

    test "returns :filtered as a fallback (null duration excluded by a duration filter)" do
      {source, item} = build(%{min_duration_seconds: 600}, %{duration_seconds: nil})

      assert SkipReason.reason(item, source) == :filtered
    end
  end

  # The Skipped tab's reason dropdown filters in SQL while the per-row chip is
  # computed in Elixir. These lock the two together - if a clause of
  # `MediaQuery.skip_reason_is/1` drifts from `SkipReason.reason/2`, an item ends
  # up filterable under the wrong reason (or, when a NULL sneaks into a negated
  # comparison, under none at all).
  describe "skip_reason_is/1 agrees with reason/2" do
    setup do
      {source, _} = build(%{}, %{})
      {:ok, source: source}
    end

    test "matches each item under exactly the reason its chip shows", %{source: source} do
      cases = [
        {:unavailable, %{unavailable_at: DateTime.utc_now(), unavailable_reason: "members-only"}},
        {:removed, %{culled_at: DateTime.utc_now()}},
        {:ignored, %{prevent_download: true}}
      ]

      for {expected, attrs} <- cases do
        item = media_item_fixture(Map.merge(%{source_id: source.id, media_filepath: nil}, attrs))

        assert SkipReason.reason(item, source) == expected
        assert_only_reason(source, item, expected)

        Repo.delete!(item)
      end
    end

    # These three depend on the source (or its profile) rather than the item
    # alone, so each needs its own source. `:title_filter` is the one most worth
    # pinning down: the SQL clause runs SQLean's `regexp_like` while the chip runs
    # Elixir's `Regex`, so a semantics divergence would silently split the two.
    test "matches an item excluded by the download cutoff date" do
      {source, item} =
        build(%{download_cutoff_date: ~D[2023-01-01]}, %{uploaded_at: ~U[2022-06-01 00:00:00Z]})

      assert SkipReason.reason(item, source) == :before_cutoff
      assert_only_reason(source, item, :before_cutoff)
    end

    test "matches a Short excluded by the profile's format rules" do
      {source, item} = build(%{profile: %{shorts_behaviour: :exclude}}, %{short_form_content: true})

      assert SkipReason.reason(item, source) == :format_excluded
      assert_only_reason(source, item, :format_excluded)
    end

    test "matches an item whose title doesn't match the source's regex" do
      {source, item} = build(%{title_filter_regex: "MATCHME"}, %{title: "totally different"})

      assert SkipReason.reason(item, source) == :title_filter
      assert_only_reason(source, item, :title_filter)
    end

    test "doesn't claim :title_filter for an item whose title DOES match the regex" do
      {source, item} = build(%{title_filter_regex: "MATCHME"}, %{title: "please MATCHME thanks"})

      refute SkipReason.reason(item, source) == :title_filter
      assert filter_ids(source, :title_filter) == []
    end

    test "a duration filter with no recorded duration is :filtered in both" do
      {source, item} = build(%{min_duration_seconds: 600}, %{duration_seconds: nil})

      assert SkipReason.reason(item, source) == :filtered
      assert filter_ids(source, :filtered) == [item.id]

      for reason <- [:too_short, :too_long] do
        assert filter_ids(source, reason) == []
      end
    end

    test "separates too short, too long, and merely filtered" do
      {source, short} = build(%{min_duration_seconds: 600, max_duration_seconds: 1200}, %{duration_seconds: 120})
      long = media_item_fixture(%{source_id: source.id, media_filepath: nil, duration_seconds: 3000})
      no_duration = media_item_fixture(%{source_id: source.id, media_filepath: nil, duration_seconds: nil})

      assert filter_ids(source, :too_short) == [short.id]
      assert filter_ids(source, :too_long) == [long.id]
      assert filter_ids(source, :filtered) == [no_duration.id]
    end

    # The dropdown offers one reason at a time, so agreement means more than "the
    # right filter finds it" - every other filter must NOT.
    defp assert_only_reason(source, item, expected) do
      assert filter_ids(source, expected) == [item.id]

      for reason <- SkipReason.all_reasons() -- [expected] do
        refute item.id in filter_ids(source, reason),
               "item is filterable under #{reason}, but its chip says #{expected}"
      end
    end

    # The Skipped tab's reason filter, applied the way the tab applies it - see
    # MediaItemTableLive's "other" media state. The tab's own not-downloaded and
    # not-pending scope is deliberately left off: `skip_reason_is/1` classifies
    # rows already known to be skipped, exactly as `SkipReason.reason/2` does, so
    # this is the classifier under test rather than the scope around it.
    defp filter_ids(source, reason) do
      alias Pinchflat.Media.MediaQuery

      MediaQuery.new()
      |> MediaQuery.require_assoc(:media_profile)
      |> where(^MediaQuery.for_source(source))
      |> where(^MediaQuery.skip_reason_is(reason))
      |> select([mi], mi.id)
      |> Repo.all()
    end
  end

  describe "for_media_item/2" do
    test "returns a presentation map with a concrete detail" do
      {source, item} = build(%{min_duration_seconds: 600}, %{duration_seconds: 120})

      result = SkipReason.for_media_item(item, source)

      assert result.reason == :too_short
      assert result.label == "Too short"
      assert result.icon == "hero-clock"
      assert result.detail == "2:00 is under the 10:00 minimum"
    end

    test "formats durations over an hour" do
      {source, item} = build(%{max_duration_seconds: 3600}, %{duration_seconds: 7325})

      result = SkipReason.for_media_item(item, source)

      assert result.detail == "2:02:05 is over the 1:00:00 maximum"
    end

    test "names the offending title pattern" do
      {source, item} = build(%{title_filter_regex: "MATCHME"}, %{title: "nope"})

      result = SkipReason.for_media_item(item, source)

      assert result.detail =~ "/MATCHME/"
    end
  end
end
