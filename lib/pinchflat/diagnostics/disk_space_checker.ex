defmodule Pinchflat.Diagnostics.DiskSpaceChecker do
  @moduledoc """
  Reports the free disk space available at a given path, using POSIX `df`.
  """

  @behaviour Pinchflat.Diagnostics.DiskSpaceBehaviour

  @doc """
  Returns the number of bytes available on the filesystem containing `path`,
  or `:error` if it can't be determined.

  Returns {:ok, non_neg_integer()} | :error
  """
  @impl Pinchflat.Diagnostics.DiskSpaceBehaviour
  def available_bytes(path) do
    with {:ok, %{available_bytes: available_bytes}} <- space_info(path), do: {:ok, available_bytes}
  end

  @doc """
  Returns free space, total space, percent used and the mount point for `path`.

  The mount point (the last `df` column) — not the device or path string — is
  what lets callers tell whether two directories live on the same volume, so a
  free-space readout isn't duplicated across collocated directories. `total_bytes`
  gives the denominator needed to show a usage bar and percentage rather than a
  bare "free" figure.

  Returns {:ok, %{available_bytes: non_neg_integer(), total_bytes: non_neg_integer(),
                  used_percent: non_neg_integer(), mountpoint: binary()}} | :error
  """
  @impl Pinchflat.Diagnostics.DiskSpaceBehaviour
  def space_info(path) do
    case System.cmd("df", ["-P", "-k", path], stderr_to_stdout: true) do
      {output, 0} -> parse_space_info(output)
      _ -> :error
    end
  rescue
    # eg: `df` not found on the system
    ErlangError -> :error
  end

  # POSIX `df -P -k` output looks like:
  #
  #   Filesystem 1024-blocks    Used Available Capacity Mounted on
  #   /dev/vda1     41152812 9412644  29617236      25% /
  #
  # The mount point is the last field; with `-P` it's a single field per row, but
  # can itself contain spaces, so everything from column 5 on is rejoined.
  defp parse_space_info(output) do
    with [_header, data_line | _] <- String.split(output, "\n", trim: true),
         columns when length(columns) >= 6 <- String.split(data_line, ~r/\s+/, trim: true),
         {total_kb, _} <- Integer.parse(Enum.at(columns, 1)),
         {available_kb, _} <- Integer.parse(Enum.at(columns, 3)),
         {used_percent, _} <- Integer.parse(String.trim_trailing(Enum.at(columns, 4), "%")) do
      {:ok,
       %{
         available_bytes: available_kb * 1024,
         total_bytes: total_kb * 1024,
         used_percent: used_percent,
         mountpoint: columns |> Enum.drop(5) |> Enum.join(" ")
       }}
    else
      _ -> :error
    end
  end
end
