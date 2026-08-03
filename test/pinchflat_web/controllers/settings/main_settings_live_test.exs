defmodule PinchflatWeb.Settings.MainSettingsLiveTest do
  use PinchflatWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Pinchflat.Settings
  alias Pinchflat.Reconciliation
  alias Pinchflat.Settings.MainSettingsLive

  defp mount_section(conn, section) do
    live_isolated(conn, MainSettingsLive, session: %{"section" => section})
  end

  # Simulates a single field auto-saving via the form-level phx-change. `extra`
  # lets a test include companion fields (eg: the yt-dlp policy + version group).
  defp change(view, field, value, extra \\ %{}) do
    setting = Map.merge(%{to_string(field) => to_string(value)}, extra)
    render_change(view, "save", %{"_target" => ["setting", to_string(field)], "setting" => setting})
  end

  describe "initial rendering" do
    test "renders only the requested section's fields", %{conn: conn} do
      {:ok, _view, html} = mount_section(conn, "integrations")

      assert html =~ ~s(name="setting[apprise_server]")
      assert html =~ ~s(name="setting[podcast_url_base]")
      refute html =~ ~s(name="setting[yt_dlp_update_policy]")
    end

    test "has no explicit save button (auto-save)", %{conn: conn} do
      {:ok, _view, html} = mount_section(conn, "system")

      assert html =~ ~s(name="setting[yt_dlp_update_policy]")
      refute html =~ "Save Settings"
    end
  end

  describe "auto-saving" do
    test "persists a text field on change and confirms with an inline Saved indicator", %{conn: conn} do
      {:ok, view, _html} = mount_section(conn, "integrations")

      html = change(view, :apprise_server, "test://server")

      assert html =~ "Saved"
      assert Settings.get!(:apprise_server) == "test://server"
    end

    test "persists a toggle", %{conn: conn} do
      {:ok, view, _html} = mount_section(conn, "media_output")

      change(view, :restrict_filenames, "true")

      assert Settings.get!(:restrict_filenames) == true
    end

    test "keeps an invalid value visible with an inline error and does not persist", %{conn: conn} do
      {:ok, view, _html} = mount_section(conn, "throttling")

      html = change(view, :download_throughput_limit, "100KB")

      assert html =~ "must be a number"
      assert Settings.get!(:download_throughput_limit) == nil
    end
  end

  describe "appearance section" do
    test "renders the table density and time format controls", %{conn: conn} do
      {:ok, _view, html} = mount_section(conn, "appearance")

      assert html =~ ~s(name="setting[table_density]")
      assert html =~ "Compact"
      assert html =~ "Comfortable"
      assert html =~ ~s(name="setting[time_format]")
    end

    test "persists the table density on change", %{conn: conn} do
      {:ok, view, _html} = mount_section(conn, "appearance")

      change(view, :table_density, "normal")

      assert Settings.get!(:table_density) == "normal"
    end
  end

  describe "yt-dlp policy" do
    test "kicks off a yt-dlp update when the policy changes", %{conn: conn} do
      {:ok, view, _html} = mount_section(conn, "system")

      change(view, :yt_dlp_update_policy, "nightly")

      assert_enqueued(worker: Pinchflat.YtDlp.UpdateWorker, args: %{"apply_policy" => true})
    end

    test "does not kick off an update for unrelated changes", %{conn: conn} do
      {:ok, view, _html} = mount_section(conn, "appearance")

      change(view, :time_format, "12h")

      refute_enqueued(worker: Pinchflat.YtDlp.UpdateWorker)
    end

    test "reveals the pinned version field without persisting when no version is set yet", %{conn: conn} do
      {:ok, view, _html} = mount_section(conn, "system")

      html = change(view, :yt_dlp_update_policy, "pinned")

      assert html =~ ~s(name="setting[yt_dlp_pinned_version]")
      # The policy is not persisted until a version is provided (it's required).
      assert Settings.get!(:yt_dlp_update_policy) == "stable"
    end

    test "persists the policy and version together once the version is entered", %{conn: conn} do
      {:ok, view, _html} = mount_section(conn, "system")

      change(view, :yt_dlp_update_policy, "pinned")

      render_change(view, "save", %{
        "_target" => ["setting", "yt_dlp_pinned_version"],
        "setting" => %{"yt_dlp_update_policy" => "pinned", "yt_dlp_pinned_version" => "2025.12.08"}
      })

      assert Settings.get!(:yt_dlp_update_policy) == "pinned"
      assert Settings.get!(:yt_dlp_pinned_version) == "2025.12.08"
    end
  end

  describe "reconcile plan staleness" do
    test "marks a staged plan stale when restrict_filenames changes", %{conn: conn} do
      {:ok, plan} = Reconciliation.create_plan(%{mode: :local, status: :ready})
      {:ok, view, _html} = mount_section(conn, "media_output")

      change(view, :restrict_filenames, "true")

      assert Reconciliation.get_plan!(plan.id).status == :stale
    end

    test "leaves a staged plan alone for changes that don't affect paths", %{conn: conn} do
      {:ok, plan} = Reconciliation.create_plan(%{mode: :local, status: :ready})
      {:ok, view, _html} = mount_section(conn, "integrations")

      change(view, :apprise_server, "test://server")

      assert Reconciliation.get_plan!(plan.id).status == :ready
    end
  end

  describe "test buttons" do
    test "disables the Apprise test button when no server is configured", %{conn: conn} do
      Settings.set(apprise_server: nil)

      {:ok, view, _html} = mount_section(conn, "integrations")

      assert has_element?(view, "button[phx-click=send_apprise_test][disabled]")
    end

    test "does not send an Apprise test when no server is configured", %{conn: conn} do
      Settings.set(apprise_server: nil)

      {:ok, view, _html} = mount_section(conn, "integrations")

      # Push the event directly to exercise the server-side guard even though
      # the rendered button is disabled. Mox verifies that the runner is not called.
      assert render_click(view, "send_apprise_test")
    end

    test "sends an apprise test to the configured server", %{conn: conn} do
      Settings.set(apprise_server: "test://server")

      expect(AppriseRunnerMock, :run, fn servers, args ->
        assert servers == ["test://server"]
        assert args == [title: "Tubeless Test", body: "This is a test message from Tubeless"]

        {:ok, ""}
      end)

      {:ok, view, _html} = mount_section(conn, "integrations")

      assert render_click(view, "send_apprise_test") =~ "hero-check"
    end

    test "resets the Apprise test icon", %{conn: conn} do
      Settings.set(apprise_server: "test://server")
      expect(AppriseRunnerMock, :run, fn _servers, _args -> {:ok, ""} end)

      {:ok, view, _html} = mount_section(conn, "integrations")

      assert render_click(view, "send_apprise_test") =~ "hero-check"
      send(view.pid, :reset_apprise_icon)

      html = render(view)
      assert html =~ "hero-paper-airplane"
      refute html =~ "hero-check"
    end

    test "tests the configured YouTube API key", %{conn: conn} do
      Settings.set(youtube_api_key: "GOODKEY")
      expect(YoutubeApiMock, :test_api_key, fn "GOODKEY" -> :ok end)

      {:ok, view, _html} = mount_section(conn, "credentials")

      assert render_click(view, "test_youtube_api_key") =~ "hero-check"
    end

    test "tests every YouTube API key and reports which one failed", %{conn: conn} do
      Settings.set(youtube_api_key: "GOODKEY,BADKEY")

      expect(YoutubeApiMock, :test_api_key, 2, fn
        "GOODKEY" -> :ok
        "BADKEY" -> {:error, "nope"}
      end)

      {:ok, view, _html} = mount_section(conn, "credentials")

      html = render_click(view, "test_youtube_api_key")
      assert html =~ "hero-x-mark"
      assert html =~ "Key 2 failed"
    end

    test "reports multiple failing YouTube API keys", %{conn: conn} do
      Settings.set(youtube_api_key: "BAD1, GOODKEY, BAD2")

      expect(YoutubeApiMock, :test_api_key, 3, fn
        "GOODKEY" -> :ok
        _bad_key -> {:error, "nope"}
      end)

      {:ok, view, _html} = mount_section(conn, "credentials")

      html = render_click(view, "test_youtube_api_key")
      assert html =~ "hero-x-mark"
      assert html =~ "Keys 1, 3 failed"
    end

    test "trims whitespace around YouTube API keys before testing them", %{conn: conn} do
      Settings.set(youtube_api_key: "  GOODKEY  ")
      expect(YoutubeApiMock, :test_api_key, fn "GOODKEY" -> :ok end)

      {:ok, view, _html} = mount_section(conn, "credentials")

      assert render_click(view, "test_youtube_api_key") =~ "hero-check"
    end

    test "reports an error when no YouTube API key is configured", %{conn: conn} do
      Settings.set(youtube_api_key: nil)

      {:ok, view, _html} = mount_section(conn, "credentials")

      html = render_click(view, "test_youtube_api_key")
      assert html =~ "hero-x-mark"
      assert html =~ "No API key provided"
    end

    test "reports an error when the YouTube API key field contains only commas", %{conn: conn} do
      Settings.set(youtube_api_key: " , , ")

      {:ok, view, _html} = mount_section(conn, "credentials")

      html = render_click(view, "test_youtube_api_key")
      assert html =~ "hero-x-mark"
      assert html =~ "No API key provided"
    end

    test "tests the newly-entered YouTube API key", %{conn: conn} do
      Settings.set(youtube_api_key: "OLDKEY")
      expect(YoutubeApiMock, :test_api_key, fn "NEWKEY" -> :ok end)

      {:ok, view, _html} = mount_section(conn, "credentials")

      change(view, :youtube_api_key, "NEWKEY")

      assert render_click(view, "test_youtube_api_key") =~ "hero-check"
    end

    test "resets the YouTube API test icon", %{conn: conn} do
      Settings.set(youtube_api_key: "GOODKEY")
      expect(YoutubeApiMock, :test_api_key, fn "GOODKEY" -> :ok end)

      {:ok, view, _html} = mount_section(conn, "credentials")

      assert render_click(view, "test_youtube_api_key") =~ "hero-check"
      send(view.pid, :reset_api_icon)

      html = render(view)
      assert html =~ "hero-play"
      refute html =~ "hero-check"
    end

    test "checks whether a pinned version is available", %{conn: conn} do
      Settings.set(yt_dlp_pinned_version: "2025.12.08")
      Settings.set(yt_dlp_update_policy: "pinned")
      expect(HTTPClientMock, :get, fn _url, _headers -> {:ok, "{}"} end)

      {:ok, view, _html} = mount_section(conn, "system")

      assert render_click(view, "check_version") =~ "hero-check"
    end

    test "reports when a pinned version is unavailable", %{conn: conn} do
      Settings.set(yt_dlp_pinned_version: "9999.99.99")
      Settings.set(yt_dlp_update_policy: "pinned")
      expect(HTTPClientMock, :get, fn _url, _headers -> {:error, "not found"} end)

      {:ok, view, _html} = mount_section(conn, "system")

      html = render_click(view, "check_version")
      assert html =~ "hero-x-mark"
      assert html =~ "Version not found"
    end

    test "disables version checking when the pinned version is blank", %{conn: conn} do
      Settings.set(yt_dlp_update_policy: "stable")

      {:ok, view, _html} = mount_section(conn, "system")
      change(view, :yt_dlp_update_policy, "pinned")

      assert has_element?(view, "button[phx-click=check_version][disabled]")
    end

    test "resets the pinned-version test icon", %{conn: conn} do
      Settings.set(yt_dlp_pinned_version: "2025.12.08")
      Settings.set(yt_dlp_update_policy: "pinned")
      expect(HTTPClientMock, :get, fn _url, _headers -> {:ok, "{}"} end)

      {:ok, view, _html} = mount_section(conn, "system")

      assert render_click(view, "check_version") =~ "hero-check"
      send(view.pid, :reset_version_icon)

      html = render(view)
      assert html =~ "hero-beaker"
      refute html =~ "hero-check"
    end
  end
end
