defmodule Pinchflat.Settings.ProxyFileTest do
  use ExUnit.Case, async: false

  alias Pinchflat.Settings.ProxyFile

  setup do
    base_dir =
      Path.join([System.tmp_dir!(), "proxy_file_test", Integer.to_string(:erlang.unique_integer([:positive]))])

    File.mkdir_p!(base_dir)
    original = Application.get_env(:pinchflat, :extras_directory)
    Application.put_env(:pinchflat, :extras_directory, base_dir)

    on_exit(fn ->
      Application.put_env(:pinchflat, :extras_directory, original)
      File.rm_rf!(base_dir)
    end)

    {:ok, base_dir: base_dir}
  end

  defp write_proxy(contents), do: File.write!(ProxyFile.filepath(), contents)

  @sample [
    %{
      "time" => 1.23,
      "city" => "Unknown city",
      "country" => "Germany",
      "host" => "203.0.113.10",
      "protocol" => "http",
      "port" => 8080,
      "username" => "",
      "password" => ""
    }
  ]

  describe "filepath/0" do
    test "points at proxy.json in the extras directory", %{base_dir: base_dir} do
      assert ProxyFile.filepath() == Path.join(base_dir, "proxy.json")
    end
  end

  describe "present?/0" do
    test "is false when missing or blank" do
      refute ProxyFile.present?()
      write_proxy("  \n ")
      refute ProxyFile.present?()
    end

    test "is true when populated" do
      write_proxy(Jason.encode!(@sample))
      assert ProxyFile.present?()
    end
  end

  describe "parse/0 and validate/0" do
    test "returns :empty for a blank or missing file" do
      assert {:error, :empty} = ProxyFile.parse()
      write_proxy("")
      assert {:error, :empty} = ProxyFile.parse()
    end

    test "returns :invalid for non-JSON, non-list, or entries missing host/port" do
      write_proxy("not json")
      assert {:error, :invalid} = ProxyFile.parse()

      write_proxy(Jason.encode!(%{"host" => "x"}))
      assert {:error, :invalid} = ProxyFile.parse()

      write_proxy(Jason.encode!([%{"protocol" => "http"}]))
      assert {:error, :invalid} = ProxyFile.parse()
    end

    test "parses usable entries and summarizes countries" do
      write_proxy(Jason.encode!(@sample))
      assert {:ok, [%{"host" => "203.0.113.10"}]} = ProxyFile.parse()
      assert {:ok, %{count: 1, countries: ["Germany"]}} = ProxyFile.validate()
    end
  end

  describe "construct_proxy_string/1" do
    test "defaults protocol to http and omits auth when no username" do
      assert ProxyFile.construct_proxy_string(%{"host" => "h", "port" => 8080}) == "http://h:8080"
    end

    test "uses the given protocol and includes auth when username present" do
      proxy = %{"protocol" => "socks5", "host" => "h", "port" => 1080, "username" => "u", "password" => "p"}
      assert ProxyFile.construct_proxy_string(proxy) == "socks5://u:p@h:1080"
    end
  end

  describe "random_proxy_url/0" do
    test "builds a URL from a randomly picked entry" do
      write_proxy(Jason.encode!(@sample))
      assert {:ok, "http://203.0.113.10:8080"} = ProxyFile.random_proxy_url()
    end

    test "propagates the empty/invalid error" do
      assert {:error, :empty} = ProxyFile.random_proxy_url()
    end
  end
end
