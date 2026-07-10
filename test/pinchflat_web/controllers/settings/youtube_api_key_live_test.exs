defmodule PinchflatWeb.Settings.YoutubeApiKeyLiveTest do
  use PinchflatWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Pinchflat.Settings.YoutubeApiKeyLive

  describe "initial rendering" do
    test "renders the API key input with the session value", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, YoutubeApiKeyLive, session: %{"value" => "ABC123"})

      assert html =~ ~s(name="setting[youtube_api_key]")
      assert html =~ ~s(value="ABC123")
      assert html =~ "Test API Key"
    end
  end

  describe "testing API keys" do
    test "shows a checkmark when the key is valid", %{conn: conn} do
      expect(YoutubeApiMock, :test_api_key, fn "GOODKEY" -> :ok end)

      {:ok, view, _html} = live_isolated(conn, YoutubeApiKeyLive, session: %{"value" => "GOODKEY"})

      html = render_click(view, "test_youtube_api_key")

      assert html =~ "hero-check"
    end

    test "tests every key and reports which one failed", %{conn: conn} do
      expect(YoutubeApiMock, :test_api_key, 2, fn
        "GOODKEY" -> :ok
        "BADKEY" -> {:error, "nope"}
      end)

      {:ok, view, _html} = live_isolated(conn, YoutubeApiKeyLive, session: %{"value" => "GOODKEY,BADKEY"})

      html = render_click(view, "test_youtube_api_key")

      assert html =~ "hero-x-mark"
      assert html =~ "Key 2 failed"
    end

    test "reports multiple failing keys", %{conn: conn} do
      expect(YoutubeApiMock, :test_api_key, 3, fn
        "GOODKEY" -> :ok
        _bad_key -> {:error, "nope"}
      end)

      {:ok, view, _html} = live_isolated(conn, YoutubeApiKeyLive, session: %{"value" => "BAD1, GOODKEY, BAD2"})

      html = render_click(view, "test_youtube_api_key")

      assert html =~ "Keys 1, 3 failed"
    end

    test "trims whitespace around keys before testing them", %{conn: conn} do
      expect(YoutubeApiMock, :test_api_key, fn "GOODKEY" -> :ok end)

      {:ok, view, _html} = live_isolated(conn, YoutubeApiKeyLive, session: %{"value" => "  GOODKEY  "})

      html = render_click(view, "test_youtube_api_key")

      assert html =~ "hero-check"
    end

    test "shows an error when no key is set", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, YoutubeApiKeyLive, session: %{"value" => nil})

      html = render_click(view, "test_youtube_api_key")

      assert html =~ "hero-x-mark"
      assert html =~ "No API key provided"
    end

    test "shows an error when the key is blank or only commas", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, YoutubeApiKeyLive, session: %{"value" => " , , "})

      html = render_click(view, "test_youtube_api_key")

      assert html =~ "No API key provided"
    end

    test "resets the button icon after a delay", %{conn: conn} do
      expect(YoutubeApiMock, :test_api_key, fn _key -> :ok end)

      {:ok, view, _html} = live_isolated(conn, YoutubeApiKeyLive, session: %{"value" => "GOODKEY"})

      assert render_click(view, "test_youtube_api_key") =~ "hero-check"

      send(view.pid, :reset_button_icon)

      assert render(view) =~ "hero-play"
    end
  end

  describe "changing the key in the form" do
    test "tests the newly-entered value rather than the saved one", %{conn: conn} do
      expect(YoutubeApiMock, :test_api_key, fn "NEWKEY" -> :ok end)

      {:ok, view, _html} = live_isolated(conn, YoutubeApiKeyLive, session: %{"value" => "OLDKEY"})

      render_change(view, "youtube_api_key_changed", %{"setting" => %{"youtube_api_key" => "NEWKEY"}})
      html = render_click(view, "test_youtube_api_key")

      assert html =~ "hero-check"
    end
  end
end
