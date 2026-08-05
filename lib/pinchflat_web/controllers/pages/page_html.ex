defmodule PinchflatWeb.Pages.PageHTML do
  use PinchflatWeb, :html

  alias Pinchflat.Utils.NumberUtils

  embed_templates "page_html/*"

  # Storage pressure is driven by *absolute* free space, not the used fraction:
  # on a 16-32GB Pi SD card shared with the OS and logs, the gigabytes left is
  # what actually matters, not the percentage. The two volumes are different
  # classes and get their own thresholds: the media volume holds large video
  # files and needs tens of gigabytes of headroom, while the database only grows
  # slowly and just needs enough room to VACUUM and grow its WAL.
  @media_amber_free_bytes 25 * 1024 * 1024 * 1024
  @media_red_free_bytes 10 * 1024 * 1024 * 1024
  @database_amber_free_bytes 500 * 1024 * 1024
  @database_red_free_bytes 250 * 1024 * 1024

  # WAL and reclaimable figures are only worth surfacing once they're big enough
  # to act on — below these they're just noise on the Database card.
  @wal_notice_bytes 4 * 1024 * 1024
  @reclaimable_notice_bytes 1 * 1024 * 1024

  @doc """
  The Activity card's headline status: what the job system is doing right now.
  """
  def activity_status(%{unavailable_queue_count: count}) when count > 0, do: {"Starting", "text-yellow-400"}
  def activity_status(%{paused_queue_count: count}) when count > 0, do: {"Paused", "text-yellow-400"}
  def activity_status(%{executing: count}) when count > 0, do: {"#{count} running", "text-green-400"}
  def activity_status(_queues), do: {"Idle", "text-white"}

  def attention_present?(attention), do: Enum.any?(attention, fn {_category, count} -> count > 0 end)

  @doc """
  Percent of the volume in use, for the storage bar width. Falls back to 0 when
  `df` couldn't report (the bar renders empty rather than crashing).
  """
  def storage_used_percent(%{used_percent: percent}) when is_integer(percent), do: percent
  def storage_used_percent(_storage), do: 0

  @doc """
  The free-space label shown under a storage bar, eg "341 GiB free (26%)".
  """
  def storage_free_label(%{available_bytes: nil}), do: "Unavailable"

  def storage_free_label(%{available_bytes: bytes, used_percent: percent}) when is_integer(percent) do
    "#{format_bytes(bytes)} free (#{percent}% used)"
  end

  def storage_free_label(%{available_bytes: bytes}), do: "#{format_bytes(bytes)} free"

  @doc """
  Tailwind fill colour for a storage bar, escalating as free space runs low.
  Thresholds differ by volume class: the media volume goes amber under ~25GB
  free and red under ~10GB; the database volume amber under ~750MB and red under
  ~500MB.
  """
  def storage_pressure_class(storage, kind)

  def storage_pressure_class(%{available_bytes: bytes}, :media) when is_integer(bytes),
    do: pressure_class(bytes, @media_red_free_bytes, @media_amber_free_bytes)

  def storage_pressure_class(%{available_bytes: bytes}, :database) when is_integer(bytes),
    do: pressure_class(bytes, @database_red_free_bytes, @database_amber_free_bytes)

  def storage_pressure_class(_storage, _kind), do: "bg-primary"

  defp pressure_class(bytes, red, _amber) when bytes < red, do: "bg-red-500"
  defp pressure_class(bytes, _red, amber) when bytes < amber, do: "bg-yellow-500"
  defp pressure_class(_bytes, _red, _amber), do: "bg-primary"

  @doc """
  Whether a storage stat has enough info to render a usage bar.
  """
  def storage_measured?(%{available_bytes: bytes}), do: is_integer(bytes)

  @doc """
  A compact "reclaimable by vacuum" note for the Database card, or nil when it's
  too small to matter.
  """
  def reclaimable_notice(%{reclaimable_bytes: bytes}) when bytes >= @reclaimable_notice_bytes,
    do: "#{format_bytes(bytes)} reclaimable"

  def reclaimable_notice(_database), do: nil

  @doc """
  A WAL-size note for the Database card, surfaced only once the WAL is large
  enough to be worth watching (a runaway `-wal` on a full disk is a corruption
  path).
  """
  def wal_notice(%{wal_bytes: bytes}) when bytes >= @wal_notice_bytes,
    do: "WAL #{format_bytes(bytes)}"

  def wal_notice(_database), do: nil

  @doc """
  Formats a byte count as a human-readable binary-unit string, eg "341.2 GiB".
  Precision follows the unit (see `NumberUtils.human_byte_size/2`) so the
  summary cards stay compact without throwing away meaningful digits.
  """
  def format_bytes(bytes) do
    {num, suffix} = NumberUtils.human_byte_size(bytes)
    "#{num} #{suffix}"
  end
end
