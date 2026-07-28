defmodule Pinchflat.Settings.ProxyTest do
  use Pinchflat.DataCase

  alias Pinchflat.Settings
  alias Pinchflat.Settings.Proxy
  alias Pinchflat.Settings.ProxyFile

  setup do
    base_dir =
      Path.join([System.tmp_dir!(), "proxy_test", Integer.to_string(:erlang.unique_integer([:positive]))])

    File.mkdir_p!(base_dir)
    original = Application.get_env(:pinchflat, :extras_directory)
    Application.put_env(:pinchflat, :extras_directory, base_dir)

    on_exit(fn ->
      Application.put_env(:pinchflat, :extras_directory, original)
      File.rm_rf!(base_dir)
    end)

    :ok
  end

  describe "resolve_url/0" do
    test "returns nil in none mode" do
      Settings.set(proxy_mode: "none")
      assert Proxy.resolve_url() == nil
    end

    test "returns the manual URL in manual mode" do
      Settings.set(proxy_url: "http://user:pass@host:8080")
      Settings.set(proxy_mode: "manual")
      assert Proxy.resolve_url() == "http://user:pass@host:8080"
    end

    test "returns a URL built from proxy.json in file mode" do
      File.write!(ProxyFile.filepath(), Jason.encode!([%{"host" => "203.0.113.10", "port" => 8080}]))
      Settings.set(proxy_mode: "file")
      assert Proxy.resolve_url() == "http://203.0.113.10:8080"
    end

    test "falls back to nil in file mode when proxy.json is empty" do
      Settings.set(proxy_mode: "file")
      assert Proxy.resolve_url() == nil
    end
  end

  describe "ytdlp_option/0" do
    test "is empty in none mode" do
      Settings.set(proxy_mode: "none")
      assert Proxy.ytdlp_option() == []
    end

    test "is [proxy: url] when a proxy resolves" do
      Settings.set(proxy_url: "http://host:8080")
      Settings.set(proxy_mode: "manual")
      assert Proxy.ytdlp_option() == [proxy: "http://host:8080"]
    end
  end

  describe "http_enabled?/0" do
    test "is false unless opted in AND a proxy resolves" do
      Settings.set(proxy_url: "http://host:8080")
      Settings.set(proxy_mode: "manual")
      Settings.set(proxy_covers_http: false)
      refute Proxy.http_enabled?()

      Settings.set(proxy_covers_http: true)
      assert Proxy.http_enabled?()

      Settings.set(proxy_mode: "none")
      refute Proxy.http_enabled?()
    end
  end

  describe "http_proxy_config/0" do
    test "parses an http proxy with auth into httpc pieces" do
      Settings.set(proxy_url: "http://user:pass@host:3128")
      Settings.set(proxy_mode: "manual")

      assert {:ok, %{host: ~c"host", port: 3128, auth: {"user", "pass"}}} = Proxy.http_proxy_config()
    end

    test "reports SOCKS proxies as unsupported for the http path" do
      Settings.set(proxy_url: "socks5://host:1080")
      Settings.set(proxy_mode: "manual")

      assert {:error, :unsupported_scheme} = Proxy.http_proxy_config()
    end

    test "reports https (TLS-to-proxy) proxies as unsupported for the http path" do
      # :httpc can't speak TLS to the proxy itself, so an https proxy can't cover
      # RSS/API traffic even though yt-dlp handles it fine.
      Settings.set(proxy_url: "https://host:8443")
      Settings.set(proxy_mode: "manual")

      assert {:error, :unsupported_scheme} = Proxy.http_proxy_config()
    end

    test "is :none when no proxy is configured" do
      Settings.set(proxy_mode: "none")
      assert Proxy.http_proxy_config() == :none
    end
  end

  describe "test_connectivity/1" do
    test "rejects SOCKS and https proxies without attempting a connection" do
      assert {:error, :unsupported_scheme} = Proxy.test_connectivity("socks5://host:1080")
      assert {:error, :unsupported_scheme} = Proxy.test_connectivity("https://host:8443")
    end

    test "returns a humanized (not raw) error for a refused connection" do
      assert {:error, message} = Proxy.test_connectivity("http://127.0.0.1:1")
      assert is_binary(message)
      # Never a raw inspected tuple like "{:failed_connect, ...}"
      refute message =~ "failed_connect"
      assert message =~ "refused" or message =~ "connect" or message =~ "timed out"
    end
  end
end
