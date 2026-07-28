defmodule Pinchflat.HTTP.HTTPClient do
  @moduledoc """
  This module provides a simple interface for making HTTP requests.

  Made to be easily swappable with other HTTP clients. If you need more complexity
  or security, check out HTTPoison or Mint.

  When the user has enabled "also proxy RSS/API traffic" (see
  `Pinchflat.Settings.Proxy`), GET requests are routed through a dedicated,
  lazily-started `:httpc` profile whose proxy option is set per request. A
  separate profile keeps proxying scoped to this client and off the default
  profile. Note `:httpc` cannot do SOCKS proxies — a SOCKS proxy falls back to a
  direct connection here (yt-dlp still honours it).
  """

  require Logger

  alias Pinchflat.HTTP.HTTPBehaviour
  alias Pinchflat.Settings.Proxy

  @behaviour HTTPBehaviour

  @proxy_profile :pinchflat_proxy

  @doc """
  Makes a GET request to the given URL and returns the response.

  NOTE: I can't really test this with Mox and I can't think of a way to test this
  that isn't ultimately redundant. I'm just going to leave it untested for now and
  focus more on testing the consumers of this module.

  Returns {:ok, String.t()} | {:error, String.t()}
  """
  @impl HTTPBehaviour
  def get(url, headers \\ [], opts \\ []) do
    headers = parse_headers(headers)
    {profile, http_options} = proxy_request_config()

    case :httpc.request(:get, {url, headers}, http_options, opts, profile) do
      {:ok, {{_version, 200, _reason_phrase}, _headers, body}} ->
        {:ok, to_string(body)}

      {:ok, {{_version, status_code, reason_phrase}, _headers, _body}} ->
        {:error, "HTTP request failed with status code #{status_code}: #{reason_phrase}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{reason}"}
    end
  end

  @doc """
  Name of the dedicated `:httpc` profile used for proxied requests, starting it
  if necessary. Also used by `Pinchflat.Settings.Proxy` for the connectivity test.
  """
  def proxy_profile do
    case :inets.start(:httpc, profile: @proxy_profile) do
      {:ok, _pid} -> @proxy_profile
      {:error, {:already_started, _pid}} -> @proxy_profile
    end
  end

  # Decides which httpc profile to use and what HTTPOptions to pass. When the
  # user hasn't opted into HTTP proxying (or the proxy is SOCKS/unusable here),
  # this uses the default profile with no proxy HTTPOptions.
  defp proxy_request_config do
    if Proxy.http_enabled?() do
      case Proxy.http_proxy_config() do
        {:ok, %{host: host, port: port, auth: auth}} ->
          profile = proxy_profile()
          :httpc.set_options([{:proxy, {{host, port}, []}}], profile)
          {profile, proxy_auth_opts(auth)}

        {:error, :unsupported_scheme} ->
          Logger.warning(
            "Proxy scheme can't be used for RSS/API calls (only http proxies are supported here; " <>
              "https/SOCKS work for yt-dlp only); connecting directly"
          )

          {:default, []}

        _ ->
          {:default, []}
      end
    else
      {:default, []}
    end
  end

  defp proxy_auth_opts(nil), do: []
  defp proxy_auth_opts({user, pass}), do: [proxy_auth: {to_charlist(user), to_charlist(pass)}]

  defp parse_headers(headers) do
    Enum.map(headers, fn {k, v} -> {to_charlist(k), to_charlist(v)} end)
  end
end
