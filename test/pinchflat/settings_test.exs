defmodule Pinchflat.SettingsTest do
  use Pinchflat.DataCase

  alias Pinchflat.Settings
  alias Pinchflat.Settings.Setting

  # NOTE: We're treating some of these tests differently
  # than in other modules because certain settings
  # are always created on app boot (including in the test env),
  # so we can't treat these like a clean slate.

  setup do
    # Ensure we have a clean slate
    Settings.set(onboarding: false)
    Settings.set(yt_dlp_version: nil)

    :ok
  end

  describe "record/0" do
    test "returns the only setting" do
      assert %Setting{} = Settings.record()
    end
  end

  describe "update_setting/2" do
    test "updates the setting" do
      setting = Settings.record()

      assert {:ok, false} = Settings.get(:onboarding)
      assert {:ok, %Setting{}} = Settings.update_setting(setting, %{onboarding: true})
      assert {:ok, true} = Settings.get(:onboarding)
    end

    test "accepts an absolute http(s) podcast URL base" do
      setting = Settings.record()

      assert {:ok, %Setting{}} = Settings.update_setting(setting, %{podcast_url_base: "http://pods.local"})
      assert {:ok, %Setting{}} = Settings.update_setting(setting, %{podcast_url_base: "https://pods.example.com/feeds"})
    end

    test "rejects a non-URL podcast URL base" do
      setting = Settings.record()

      assert {:error, %Ecto.Changeset{}} = Settings.update_setting(setting, %{podcast_url_base: "pods.local"})
      assert {:error, %Ecto.Changeset{}} = Settings.update_setting(setting, %{podcast_url_base: "ftp://pods.local"})
    end

    test "rejects a podcast URL base with XML-unsafe characters or query/fragment" do
      setting = Settings.record()

      # A quote would otherwise break/inject the enclosure XML attribute
      assert {:error, %Ecto.Changeset{}} =
               Settings.update_setting(setting, %{podcast_url_base: ~s(https://pods.local/"x="y)})

      assert {:error, %Ecto.Changeset{}} =
               Settings.update_setting(setting, %{podcast_url_base: "https://pods.local?a=b"})

      assert {:error, %Ecto.Changeset{}} =
               Settings.update_setting(setting, %{podcast_url_base: "https://pods.local#frag"})

      assert {:error, %Ecto.Changeset{}} = Settings.update_setting(setting, %{podcast_url_base: "https://"})
    end

    test "allows clearing the podcast URL base" do
      setting = Settings.record()

      assert {:ok, %Setting{}} = Settings.update_setting(setting, %{podcast_url_base: ""})
      assert {:ok, nil} = Settings.get(:podcast_url_base)
    end

    test "kicks off a podcast sweep when the URL base changes" do
      setting = Settings.record()

      assert {:ok, _} = Settings.update_setting(setting, %{podcast_url_base: "http://pods.local"})

      assert_enqueued(worker: Pinchflat.Podcasts.PodcastSweepWorker)
    end

    test "does not kick off a podcast sweep for unrelated changes" do
      setting = Settings.record()

      assert {:ok, _} = Settings.update_setting(setting, %{onboarding: true})

      refute_enqueued(worker: Pinchflat.Podcasts.PodcastSweepWorker)
    end

    test "set/1 also triggers the podcast sweep on a URL-base change" do
      assert {:ok, _} = Settings.set(podcast_url_base: "http://pods.local")

      assert_enqueued(worker: Pinchflat.Podcasts.PodcastSweepWorker)
    end
  end

  describe "set/1" do
    test "updates the setting" do
      assert {:ok, true} = Settings.set(onboarding: true)
      assert {:ok, true} = Settings.get(:onboarding)
    end

    test "returns an error if the setting key doesn't exist" do
      assert {:error, :invalid_key} = Settings.set(foo: "bar")
    end

    test "returns an error if the setting value is invalid" do
      assert {:error, %Ecto.Changeset{}} = Settings.set(onboarding: "bar")
    end
  end

  describe "get/1" do
    test "returns the setting value" do
      assert {:ok, false} = Settings.get(:onboarding)
    end

    test "returns an error if the setting key doesn't exist" do
      assert {:error, :invalid_key} = Settings.get(:foo)
    end
  end

  describe "get!/1" do
    test "returns the setting value" do
      assert Settings.get!(:onboarding) == false
    end

    test "raises an error if the setting key doesn't exist" do
      assert_raise RuntimeError, "Setting `foo` not found", fn ->
        Settings.get!(:foo)
      end
    end
  end

  describe "change_setting/2" do
    test "returns a changeset" do
      setting = Settings.record()

      assert %Ecto.Changeset{} = Settings.change_setting(setting, %{onboarding: true})
    end

    test "ensures the extractor sleep interval is positive" do
      setting = Settings.record()

      assert %Ecto.Changeset{valid?: true} = Settings.change_setting(setting, %{extractor_sleep_interval_seconds: 1})
      assert %Ecto.Changeset{valid?: true} = Settings.change_setting(setting, %{extractor_sleep_interval_seconds: 0})
      assert %Ecto.Changeset{valid?: false} = Settings.change_setting(setting, %{extractor_sleep_interval_seconds: -1})
    end

    test "allows you to reset the extractor sleep interval" do
      setting = Settings.record()
      assert {:ok, setting} = Settings.update_setting(setting, %{extractor_sleep_interval_seconds: 1})

      assert %Ecto.Changeset{valid?: true} = Settings.change_setting(setting, %{extractor_sleep_interval_seconds: 0})
    end

    test "only allows known yt-dlp update policies" do
      setting = Settings.record()

      assert %Ecto.Changeset{valid?: true} = Settings.change_setting(setting, %{yt_dlp_update_policy: "nightly"})
      assert %Ecto.Changeset{valid?: false} = Settings.change_setting(setting, %{yt_dlp_update_policy: "bogus"})
    end

    test "requires a pinned version when the policy is pinned" do
      setting = Settings.record()

      assert %Ecto.Changeset{valid?: false} = Settings.change_setting(setting, %{yt_dlp_update_policy: "pinned"})

      assert %Ecto.Changeset{valid?: true} =
               Settings.change_setting(setting, %{yt_dlp_update_policy: "pinned", yt_dlp_pinned_version: "2025.12.08"})
    end

    test "validates the download throughput limit format" do
      setting = Settings.record()

      assert %Ecto.Changeset{valid?: true} = Settings.change_setting(setting, %{download_throughput_limit: "50K"})
      assert %Ecto.Changeset{valid?: true} = Settings.change_setting(setting, %{download_throughput_limit: "4.2M"})
      assert %Ecto.Changeset{valid?: true} = Settings.change_setting(setting, %{download_throughput_limit: "500"})
      assert %Ecto.Changeset{valid?: true} = Settings.change_setting(setting, %{download_throughput_limit: ""})
      assert %Ecto.Changeset{valid?: false} = Settings.change_setting(setting, %{download_throughput_limit: "100KB"})
      assert %Ecto.Changeset{valid?: false} = Settings.change_setting(setting, %{download_throughput_limit: "fast"})
    end

    test "only allows known proxy modes" do
      setting = Settings.record()

      assert %Ecto.Changeset{valid?: true} = Settings.change_setting(setting, %{proxy_mode: "none"})
      assert %Ecto.Changeset{valid?: true} = Settings.change_setting(setting, %{proxy_mode: "file"})
      assert %Ecto.Changeset{valid?: false} = Settings.change_setting(setting, %{proxy_mode: "bogus"})
    end

    test "requires a valid proxy URL when the mode is manual" do
      setting = Settings.record()

      assert %Ecto.Changeset{valid?: false} = Settings.change_setting(setting, %{proxy_mode: "manual"})

      assert %Ecto.Changeset{valid?: false} =
               Settings.change_setting(setting, %{proxy_mode: "manual", proxy_url: "not a url"})

      assert %Ecto.Changeset{valid?: true} =
               Settings.change_setting(setting, %{proxy_mode: "manual", proxy_url: "http://user:pass@host:8080"})

      assert %Ecto.Changeset{valid?: true} =
               Settings.change_setting(setting, %{proxy_mode: "manual", proxy_url: "socks5://host:1080"})
    end
  end
end
