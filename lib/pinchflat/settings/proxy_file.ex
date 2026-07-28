defmodule Pinchflat.Settings.ProxyFile do
  @moduledoc """
  Manages the user-provided `proxy.json` file — a list of proxies that yt-dlp
  can rotate through. One proxy is picked at random per yt-dlp invocation (see
  `Pinchflat.Settings.Proxy`).

  The file lives in the configured `:extras_directory` and is created (blank) on
  boot by `Pinchflat.Boot.PreJobStartupTasks`, exactly like `cookies.txt`. An
  empty or missing file is treated as "no proxies".

  Expected format (only host/port/protocol/username/password are used; the rest
  is informational):

      [
        {
          "time": 1.23,
          "city": "Unknown city",
          "country": "Germany",
          "host": "203.0.113.10",
          "protocol": "http",
          "port": 8080,
          "username": "",
          "password": ""
        }
      ]
  """

  alias Pinchflat.Utils.FilesystemUtils, as: FSUtils

  @filename "proxy.json"

  @doc """
  Returns the absolute path to the proxy file.
  """
  def filepath do
    base_dir = Application.get_env(:pinchflat, :extras_directory)
    Path.join(base_dir, @filename)
  end

  @doc """
  Returns true if a proxy file exists and has non-whitespace contents.
  """
  def present? do
    FSUtils.exists_and_nonempty?(filepath())
  end

  @doc """
  Reads the raw contents of the proxy file.

  Returns {:ok, binary()} | {:error, File.posix()}
  """
  def read do
    File.read(filepath())
  end

  @doc """
  Replaces the proxy file with the contents at `source_path` (e.g. an uploaded
  temp file). Ensures the destination directory exists.

  Returns :ok | {:error, File.posix()}
  """
  def save_from_path(source_path) do
    dest = filepath()
    File.mkdir_p!(Path.dirname(dest))
    File.cp(source_path, dest)
  end

  @doc """
  Clears the proxy file by writing blank contents (rather than deleting it, to
  keep the boot-time invariant that the file exists).

  Returns :ok | {:error, File.posix()}
  """
  def clear do
    File.write(filepath(), "")
  end

  @doc """
  Parses the proxy file into a list of proxy maps.

  Returns:
    - {:ok, [map()]}
    - {:error, :empty}   — file missing or blank
    - {:error, :invalid} — not valid JSON, not a list, or no usable entries
  """
  def parse do
    case read() do
      {:ok, contents} -> parse_contents(contents)
      {:error, _} -> {:error, :empty}
    end
  end

  @doc """
  Validates the proxy file and returns a small summary for the UI.

  Returns:
    - {:ok, %{count: n, countries: [binary()]}}
    - {:error, :empty | :invalid}
  """
  def validate do
    case parse() do
      {:ok, proxies} ->
        countries =
          proxies
          |> Enum.map(&Map.get(&1, "country"))
          |> Enum.reject(&(&1 in [nil, ""]))
          |> Enum.uniq()

        {:ok, %{count: length(proxies), countries: countries}}

      err ->
        err
    end
  end

  @doc """
  Picks a random proxy from the file and builds its yt-dlp proxy URL string.

  Returns {:ok, binary()} | {:error, :empty | :invalid}
  """
  def random_proxy_url do
    case parse() do
      {:ok, proxies} -> {:ok, construct_proxy_string(Enum.random(proxies))}
      err -> err
    end
  end

  @doc """
  Builds a proxy URL string from a proxy map, mirroring the reference
  `construct_proxy_string`. Protocol defaults to "http"; auth is included only
  when a username is present.
  """
  def construct_proxy_string(proxy) do
    protocol = presence(Map.get(proxy, "protocol")) || "http"

    auth_part =
      case presence(Map.get(proxy, "username")) do
        nil -> ""
        username -> "#{username}:#{Map.get(proxy, "password", "")}@"
      end

    "#{protocol}://#{auth_part}#{Map.get(proxy, "host")}:#{Map.get(proxy, "port")}"
  end

  defp parse_contents(contents) do
    if String.trim(contents) == "" do
      {:error, :empty}
    else
      case Jason.decode(contents) do
        {:ok, list} when is_list(list) -> filter_usable(list)
        _ -> {:error, :invalid}
      end
    end
  end

  # Keep only entries that have at least a host and a port — the two fields
  # required to build a usable proxy URL.
  defp filter_usable(list) do
    usable =
      Enum.filter(list, fn
        %{"host" => host, "port" => port} -> presence(host) != nil and port not in [nil, ""]
        _ -> false
      end)

    case usable do
      [] -> {:error, :invalid}
      proxies -> {:ok, proxies}
    end
  end

  defp presence(nil), do: nil
  defp presence(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  defp presence(value), do: value
end
