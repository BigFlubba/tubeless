defmodule Pinchflat.Settings.Proxy do
  @moduledoc """
  Central resolver for proxy configuration. Both the yt-dlp command runner and
  the HTTP client ask this module what proxy (if any) to use.

  Reads live settings on every call, so a settings change takes effect on the
  next yt-dlp invocation / HTTP request without a restart. In `"file"` mode a
  proxy is picked at random from `proxy.json` on each call to `resolve_url/0`.
  """

  require Logger

  alias Pinchflat.Settings
  alias Pinchflat.Settings.ProxyFile

  @doc """
  Resolves the proxy URL to use for the next network operation, or nil for a
  direct connection.
  """
  def resolve_url do
    case Settings.get!(:proxy_mode) do
      "manual" -> presence(Settings.get!(:proxy_url))
      "file" -> resolve_file_url()
      _ -> nil
    end
  end

  @doc """
  yt-dlp option list for the resolved proxy: `[]` or `[proxy: url]`.

  `CliUtils.parse_options/1` turns `[proxy: url]` into `["--proxy", url]`.
  """
  def ytdlp_option do
    case resolve_url() do
      nil -> []
      url -> [proxy: url]
    end
  end

  @doc """
  Whether Tubeless's own RSS/YouTube-API HTTP calls should be routed through the
  proxy. True only when the user opted in AND a proxy is actually resolvable.
  """
  def http_enabled? do
    Settings.get!(:proxy_covers_http) && resolve_url() != nil
  end

  @doc """
  Parses the resolved proxy into the pieces `:httpc` needs.

  `:httpc` cannot handle SOCKS proxies (only http). A SOCKS proxy therefore
  yields `{:error, :unsupported_scheme}` so the HTTP path falls back to direct
  while yt-dlp still honours it.

  Returns:
    - {:ok, %{host: charlist(), port: integer(), auth: nil | {binary(), binary()}}}
    - :none                        — no proxy resolvable
    - {:error, :unsupported_scheme | :invalid}
  """
  def http_proxy_config do
    case resolve_url() do
      nil -> :none
      url -> parse_http_proxy(url)
    end
  end

  @doc """
  Tests a proxy URL by fetching a lightweight IP-echo endpoint through it and
  returning the exit IP.

  Returns {:ok, exit_ip} | {:error, reason}
  """
  def test_connectivity(url) do
    with {:ok, %{host: host, port: port, auth: auth}} <- parse_http_proxy(url) do
      run_ip_echo(host, port, auth)
    end
  end

  defp resolve_file_url do
    case ProxyFile.random_proxy_url() do
      {:ok, url} ->
        url

      {:error, reason} ->
        Logger.warning("Proxy mode is 'file' but proxy.json is #{reason}; using a direct connection")
        nil
    end
  end

  defp parse_http_proxy(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: "http", host: host, port: port, userinfo: userinfo}}
      when is_binary(host) and host != "" ->
        {:ok, %{host: to_charlist(host), port: port || 80, auth: parse_auth(userinfo)}}

      # `:httpc` only ever connects to the proxy over plain TCP, so it can't use
      # an `https` (TLS-to-proxy) or SOCKS proxy for our own RSS/API calls or the
      # connectivity test. yt-dlp handles all of these itself, so this limitation
      # only affects the opt-in `proxy_covers_http` path and the Test button.
      {:ok, %URI{scheme: scheme}} when scheme in ["https", "socks4", "socks5", "socks5h"] ->
        {:error, :unsupported_scheme}

      _ ->
        {:error, :invalid}
    end
  end

  defp parse_auth(nil), do: nil

  defp parse_auth(userinfo) do
    case String.split(userinfo, ":", parts: 2) do
      [user, pass] -> {user, pass}
      [user] -> {user, ""}
    end
  end

  defp run_ip_echo(host, port, auth) do
    # Use a throwaway, isolated httpc profile so the test never reuses another
    # test's keep-alive connection (which would otherwise report the *previous*
    # proxy's exit IP) and never mutates the shared RSS/API proxy profile.
    profile = :"pinchflat_proxy_test_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = :inets.start(:httpc, profile: profile)

    try do
      :httpc.set_options([{:proxy, {{host, port}, []}}], profile)

      # connect_timeout bounds an unreachable/dropped proxy (which would otherwise
      # hang until `timeout`); timeout bounds the whole request.
      http_opts = [timeout: 10_000, connect_timeout: 8_000] ++ proxy_auth_opts(auth)
      endpoint = Application.get_env(:pinchflat, :proxy_test_url, "https://api.ipify.org")

      case :httpc.request(:get, {to_charlist(endpoint), []}, http_opts, [body_format: :binary], profile) do
        {:ok, {{_v, 200, _r}, _headers, body}} -> {:ok, String.trim(to_string(body))}
        {:ok, {{_v, 407, _r}, _h, _b}} -> {:error, "Proxy authentication failed (407)"}
        {:ok, {{_v, code, reason}, _h, _b}} -> {:error, "Unexpected response: HTTP #{code} #{reason}"}
        {:error, reason} -> {:error, humanize_error(reason)}
      end
    after
      :inets.stop(:httpc, pid)
    end
  end

  defp proxy_auth_opts(nil), do: []
  defp proxy_auth_opts({user, pass}), do: [proxy_auth: {to_charlist(user), to_charlist(pass)}]

  # Turn httpc's nested error terms into a short, human-readable message.
  defp humanize_error(:timeout), do: "Connection timed out"

  defp humanize_error({:failed_connect, details}) do
    posix =
      Enum.find_value(details, fn
        {:inet, _opts, reason} -> reason
        _ -> nil
      end)

    case posix do
      :econnrefused -> "Connection refused (is the proxy up and the port correct?)"
      reason when reason in [:timeout, :etimedout] -> "Connection timed out (proxy unreachable?)"
      :nxdomain -> "Proxy host not found (bad hostname?)"
      :ehostunreach -> "Proxy host unreachable"
      :enetunreach -> "Network unreachable"
      nil -> "Could not connect to the proxy"
      other -> other |> :inet.format_error() |> to_string()
    end
  end

  defp humanize_error(other), do: inspect(other)

  defp presence(nil), do: nil
  defp presence(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  defp presence(value), do: value
end
