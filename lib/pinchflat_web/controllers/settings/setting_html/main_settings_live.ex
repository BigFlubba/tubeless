defmodule Pinchflat.Settings.MainSettingsLive do
  @moduledoc """
  The plain (non-file) settings fields, auto-saving with no Save button.

  Rendered **once per `section`** (passed in the mount session) so `show.html`
  can compose the settings cards freely, interleaving these field groups with
  the file/proxy LiveViews. Each instance renders only its section's `<form>`
  and persists each field via `Settings.update_setting/2` on `phx-change`
  (selects/toggles immediately, text/number on blur), keyed off the change
  event's `_target` so only the edited field is written — except the yt-dlp
  policy/version pair, which saves as a group so a transiently-invalid "pinned
  with no version yet" state just reveals the field instead of erroring.

  Text/number fields flash an inline "Saved" confirmation on the field itself;
  toggles and selects show none (flipping/picking is its own confirmation).
  Invalid input keeps the offending value visible with an inline error and
  leaves the stored value untouched.

  The Apprise / YouTube-API / yt-dlp-version **Test** buttons live in whichever
  section renders them.
  """
  use PinchflatWeb, :live_view

  alias PinchflatWeb.Settings.SettingHTML
  alias Pinchflat.Settings
  alias Pinchflat.Reconciliation
  alias Pinchflat.YtDlp.ReleaseLookup
  alias Pinchflat.YtDlp.UpdateWorker

  # Editing the yt-dlp policy alone can leave a transiently-invalid state (pinned
  # with no version yet), so the two are always persisted together as a group.
  @yt_dlp_group ~w(yt_dlp_update_policy yt_dlp_pinned_version)

  @policy_options [
    {"Stable (recommended)", "stable"},
    {"Nightly, auto-updated", "nightly"},
    {"Nightly, frozen", "nightly_frozen"},
    {"Nightly until stable catches up", "nightly_until_stable"},
    {"Pin a specific version", "pinned"}
  ]

  def render(%{section: "throttling"} = assigns) do
    ~H"""
    <form id="settings-throttling-form" phx-change="save" phx-submit="save">
      <.input
        id="setting_download_throughput_limit"
        name="setting[download_throughput_limit]"
        value={@download_throughput_limit}
        errors={@errors[:download_throughput_limit] || []}
        placeholder="4.2M"
        label="Download Speed Cap"
        help="Sets the max bytes-per-second throughput when downloading media. Examples: '50K' or '4.2M'. Leave blank to disable"
        phx-debounce="blur"
      >
        <:input_append>
          <.saved_check show={saved_field?(@saved_field, :download_throughput_limit)} />
        </:input_append>
      </.input>

      <.input
        id="setting_extractor_sleep_interval_seconds"
        name="setting[extractor_sleep_interval_seconds]"
        value={@extractor_sleep_interval_seconds}
        errors={@errors[:extractor_sleep_interval_seconds] || []}
        placeholder="0"
        type="number"
        label="Sleep Interval (seconds)"
        help="Sleep interval in seconds between each extractor request. Must be a positive whole number. Set to 0 to disable"
        phx-debounce="blur"
      >
        <:input_append>
          <.saved_check show={saved_field?(@saved_field, :extractor_sleep_interval_seconds)} />
        </:input_append>
      </.input>
    </form>
    """
  end

  def render(%{section: "credentials"} = assigns) do
    ~H"""
    <form id="settings-credentials-form" phx-change="save" phx-submit="save">
      <div x-data="{ revealed: false }">
        <.input
          type="password"
          x-bind:type="revealed ? 'text' : 'password'"
          autocomplete="off"
          id="setting_youtube_api_key"
          name="setting[youtube_api_key]"
          value={@youtube_api_key}
          errors={@errors[:youtube_api_key] || []}
          label="YouTube API Key(s)"
          help={SettingHTML.youtube_api_help()}
          html_help={true}
          inputclass="font-mono text-sm mr-4"
          placeholder="ABC123,DEF456"
          phx-debounce="blur"
        >
          <:input_append>
            <.saved_check show={saved_field?(@saved_field, :youtube_api_key)} />
            <.icon_button
              x-cloak
              x-show="!revealed"
              x-on:click="revealed = true"
              icon_name="hero-eye"
              class="h-12 w-12 mr-2"
              tooltip="Reveal"
              type="button"
            />
            <.icon_button
              x-cloak
              x-show="revealed"
              x-on:click="revealed = false"
              icon_name="hero-eye-slash"
              class="h-12 w-12 mr-2"
              tooltip="Hide"
              type="button"
            />
            <.icon_button
              icon_name={@api_icon}
              class="h-12 w-12"
              phx-click="test_youtube_api_key"
              tooltip={@api_tooltip}
            />
          </:input_append>
        </.input>
      </div>
    </form>
    """
  end

  def render(%{section: "media_output"} = assigns) do
    ~H"""
    <form id="settings-media-output-form" phx-change="save" phx-submit="save">
      <.input
        id="setting_video_codec_preference"
        name="setting[video_codec_preference]"
        value={@video_codec_preference}
        errors={@errors[:video_codec_preference] || []}
        placeholder="avc"
        type="text"
        label="Video Codec Preference"
        help="Video codec preference (default: avc). Will be remuxed into an MP4 container. See below for more details"
        inputclass="font-mono text-sm mr-4"
        phx-debounce="blur"
      >
        <:input_append>
          <.saved_check show={saved_field?(@saved_field, :video_codec_preference)} />
        </:input_append>
      </.input>

      <.input
        id="setting_audio_codec_preference"
        name="setting[audio_codec_preference]"
        value={@audio_codec_preference}
        errors={@errors[:audio_codec_preference] || []}
        placeholder="m4a"
        type="text"
        label="Audio Codec Preference"
        help="Audio codec preference (default: m4a). See below for more details"
        inputclass="font-mono text-sm mr-4"
        phx-debounce="blur"
      >
        <:input_append>
          <.saved_check show={saved_field?(@saved_field, :audio_codec_preference)} />
        </:input_append>
      </.input>

      <.input
        id="setting_restrict_filenames"
        name="setting[restrict_filenames]"
        value={@restrict_filenames}
        type="toggle"
        label="Restrict Filenames to ASCII"
        help="Restrict filenames to only ASCII characters and avoid ampersands/spaces in filenames"
      />

      <div class="rounded-xs dark:bg-meta-4 p-4 md:p-6 mt-5">
        <SettingHTML.codec_settings_help />
      </div>
    </form>
    """
  end

  def render(%{section: "library"} = assigns) do
    ~H"""
    <form id="settings-library-form" phx-change="save" phx-submit="save">
      <.input
        id="setting_ignore_unavailable_media"
        name="setting[ignore_unavailable_media]"
        value={@ignore_unavailable_media}
        type="toggle"
        label="Ignore Unavailable Media"
        help="Mark members-only, private, and removed videos as skipped instead of repeatedly erroring. They stay in the database but won't be retried"
      />
    </form>
    """
  end

  def render(%{section: "integrations"} = assigns) do
    ~H"""
    <form id="settings-integrations-form" phx-change="save" phx-submit="save">
      <.input
        type="text"
        id="setting_apprise_server"
        name="setting[apprise_server]"
        value={@apprise_server}
        errors={@errors[:apprise_server] || []}
        label="Apprise Server"
        help={SettingHTML.apprise_server_help()}
        html_help={true}
        inputclass="font-mono text-sm mr-4"
        placeholder="https://discordapp.com/api/webhooks/{WebhookID}/{WebhookToken}"
        phx-debounce="blur"
      >
        <:input_append>
          <.saved_check show={saved_field?(@saved_field, :apprise_server)} />
          <.icon_button
            icon_name={@apprise_icon}
            class="h-12 w-12 disabled:opacity-50 disabled:cursor-not-allowed"
            phx-click="send_apprise_test"
            tooltip={@apprise_tooltip}
            disabled={blank?(@apprise_server)}
          />
        </:input_append>
      </.input>

      <p class="text-sm mt-6 max-w-prose">
        Sources with podcast export enabled are written as plain files (feeds + media) to the podcast
        export directory so a separate static web server can host them without exposing Tubeless
      </p>

      <.input
        id="setting_podcast_url_base"
        name="setting[podcast_url_base]"
        value={@podcast_url_base}
        errors={@errors[:podcast_url_base] || []}
        placeholder="http://pods.local"
        type="text"
        label="Podcast Export URL"
        help="The public URL your static web server serves the podcast export directory at. Feed links are built from this, so exports won't run until it's set"
        inputclass="font-mono text-sm mr-4"
        phx-debounce="blur"
      >
        <:input_append>
          <.saved_check show={saved_field?(@saved_field, :podcast_url_base)} />
        </:input_append>
      </.input>
    </form>
    """
  end

  def render(%{section: "system"} = assigns) do
    ~H"""
    <form id="settings-system-form" phx-change="save" phx-submit="save">
      <div class="mt-5">
        <.input
          id="setting_database_maintenance_enabled"
          name="setting[database_maintenance_enabled]"
          value={@database_maintenance_enabled}
          type="toggle"
          label="Scheduled Database Compaction"
          help="Automatically compact the database once a month to reclaim disk space. Job queues are paused while running jobs finish, then processing resumes. You can always compact manually from the Diagnostics page"
        />
      </div>

      <.input
        type="select"
        id="setting_yt_dlp_update_policy"
        name="setting[yt_dlp_update_policy]"
        value={@yt_dlp_update_policy}
        options={@policy_options}
        label="yt-dlp Updates"
        help={SettingHTML.yt_dlp_update_policy_help()}
      />

      <.input
        :if={@yt_dlp_update_policy == "pinned"}
        type="text"
        id="setting_yt_dlp_pinned_version"
        name="setting[yt_dlp_pinned_version]"
        value={@yt_dlp_pinned_version}
        errors={@errors[:yt_dlp_pinned_version] || []}
        label="Pinned Version"
        help={SettingHTML.yt_dlp_pinned_version_help()}
        html_help={true}
        inputclass="font-mono text-sm mr-4"
        placeholder="2025.12.08"
        phx-debounce="blur"
      >
        <:input_append>
          <.saved_check show={saved_field?(@saved_field, :yt_dlp_pinned_version)} />
          <.icon_button
            icon_name={@version_icon}
            class="h-12 w-12 disabled:opacity-50 disabled:cursor-not-allowed"
            phx-click="check_version"
            tooltip={@version_tooltip}
            disabled={blank?(@yt_dlp_pinned_version)}
          />
        </:input_append>
      </.input>

      <div x-data={"{ is12h: #{@time_format == "12h"} }"} phx-update="ignore" id="time-format-wrapper" class="mt-5">
        <.label for="setting_time_format">Time Format</.label>
        <div class="relative flex flex-col">
          <input
            type="hidden"
            id="setting_time_format"
            name="setting[time_format]"
            x-bind:value="is12h ? '12h' : '24h'"
          />
          <div
            class="inline-flex items-center gap-3 cursor-pointer"
            @click="is12h = !is12h; dispatchFor('setting_time_format', 'change')"
          >
            <span x-bind:class="!is12h ? 'text-black dark:text-white' : 'opacity-50'">24hr</span>
            <div class="relative h-8 w-14">
              <div x-bind:class="is12h && 'bg-primary!'" class="block h-8 w-14 rounded-full bg-black"></div>
              <div
                x-bind:class="is12h && 'right-1! translate-x-full!'"
                class="absolute left-1 top-1 flex h-6 w-6 items-center justify-center rounded-full bg-white transition"
              >
              </div>
            </div>
            <span x-bind:class="is12h ? 'text-black dark:text-white' : 'opacity-50'">12hr</span>
          </div>
          <.help>Clock used when displaying timestamps in the UI</.help>
        </div>
      </div>
    </form>
    """
  end

  attr :show, :boolean, default: false

  defp saved_check(assigns) do
    ~H"""
    <span
      :if={@show}
      class="ml-3 flex shrink-0 items-center gap-1 whitespace-nowrap text-sm font-medium text-meta-3"
      role="status"
    >
      <.icon name="hero-check-circle" class="h-5 w-5" /> Saved
    </span>
    """
  end

  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(%{
        section: session["section"] || "throttling",
        policy_options: @policy_options,
        errors: %{},
        saved_field: nil,
        apprise_icon: "hero-paper-airplane",
        apprise_tooltip: "Send Test",
        api_icon: "hero-play",
        api_tooltip: "Test API Key",
        version_icon: "hero-beaker",
        version_tooltip: "Check availability"
      })
      |> assign_values(Settings.record())

    {:ok, socket}
  end

  def handle_event("save", params, socket) do
    setting_params = params["setting"] || %{}

    {fields, edited_field} =
      case params["_target"] do
        ["setting", field] -> {group_for(field), String.to_existing_atom(field)}
        # A form submit (eg: hitting Enter) carries no target — persist everything
        # present, mirroring the old single "Save" button.
        _ -> {Map.keys(setting_params), nil}
      end

    persist(Map.take(setting_params, fields), edited_field, socket)
  end

  def handle_event("send_apprise_test", _params, %{assigns: assigns} = socket) do
    if blank?(assigns.apprise_server) do
      {:noreply, socket}
    else
      apprise_runner().run([assigns.apprise_server],
        title: "Tubeless Test",
        body: "This is a test message from Tubeless"
      )

      Process.send_after(self(), :reset_apprise_icon, 4_000)

      {:noreply, assign(socket, %{apprise_icon: "hero-check", apprise_tooltip: "Sent!"})}
    end
  end

  def handle_event("test_youtube_api_key", _params, %{assigns: assigns} = socket) do
    {icon, tooltip} =
      case test_api_key(assigns.youtube_api_key) do
        :ok -> {"hero-check", "Success!"}
        {:error, reason} -> {"hero-x-mark", reason}
      end

    Process.send_after(self(), :reset_api_icon, 4_000)
    {:noreply, assign(socket, %{api_icon: icon, api_tooltip: tooltip})}
  end

  def handle_event("check_version", _params, %{assigns: assigns} = socket) do
    if blank?(assigns.yt_dlp_pinned_version) do
      {:noreply, socket}
    else
      Process.send_after(self(), :reset_version_icon, 4_000)

      assigns =
        if ReleaseLookup.version_available?(String.trim(assigns.yt_dlp_pinned_version)) do
          %{version_icon: "hero-check", version_tooltip: "Version available"}
        else
          %{version_icon: "hero-x-mark", version_tooltip: "Version not found"}
        end

      {:noreply, assign(socket, assigns)}
    end
  end

  def handle_info(:reset_saved, socket), do: {:noreply, assign(socket, saved_field: nil)}

  def handle_info(:reset_apprise_icon, socket) do
    {:noreply, assign(socket, %{apprise_icon: "hero-paper-airplane", apprise_tooltip: "Send Test"})}
  end

  def handle_info(:reset_api_icon, socket) do
    {:noreply, assign(socket, %{api_icon: "hero-play", api_tooltip: "Test API Key"})}
  end

  def handle_info(:reset_version_icon, socket) do
    {:noreply, assign(socket, %{version_icon: "hero-beaker", version_tooltip: "Check availability"})}
  end

  defp persist(attrs, edited_field, socket) do
    old_setting = Settings.record()

    case Settings.update_setting(old_setting, attrs) do
      {:ok, updated_setting} ->
        apply_side_effects(old_setting, updated_setting)
        Process.send_after(self(), :reset_saved, 4_000)

        # Only re-read the just-saved field(s) from the DB. Reloading every field
        # would revert another field's in-progress (eg: errored) edit that the
        # user hasn't gotten back to yet.
        saved_fields = attrs |> Map.keys() |> Enum.map(&String.to_existing_atom/1)

        socket =
          socket
          |> assign_saved_fields(updated_setting, saved_fields)
          |> assign(errors: Map.drop(socket.assigns.errors, saved_fields), saved_field: edited_field)

        {:noreply, socket}

      {:error, changeset} ->
        # Keep the submitted (invalid) values visible with their inline errors;
        # the stored setting is untouched.
        socket =
          socket
          |> reflect_submitted(attrs)
          |> assign(errors: field_errors(changeset), saved_field: nil)

        {:noreply, socket}
    end
  end

  # A policy/pinned change kicks the one-shot yt-dlp update; a restrict_filenames
  # change can alter predicted paths, so any staged reconcile plan is marked stale.
  # These used to live in the settings controller — they move here now that the
  # form saves through the LiveView.
  defp apply_side_effects(old_setting, new_setting) do
    policy_changed? =
      old_setting.yt_dlp_update_policy != new_setting.yt_dlp_update_policy or
        old_setting.yt_dlp_pinned_version != new_setting.yt_dlp_pinned_version

    if policy_changed?, do: UpdateWorker.kickoff_apply()

    if old_setting.restrict_filenames != new_setting.restrict_filenames do
      Reconciliation.mark_ready_plans_stale()
    end

    :ok
  end

  defp group_for(field) when field in @yt_dlp_group, do: @yt_dlp_group
  defp group_for(field), do: [field]

  defp saved_field?(saved_field, field), do: saved_field == field

  defp assign_values(socket, setting) do
    assign(socket, %{
      apprise_server: setting.apprise_server,
      youtube_api_key: setting.youtube_api_key,
      extractor_sleep_interval_seconds: setting.extractor_sleep_interval_seconds,
      download_throughput_limit: setting.download_throughput_limit,
      restrict_filenames: setting.restrict_filenames,
      ignore_unavailable_media: setting.ignore_unavailable_media,
      database_maintenance_enabled: setting.database_maintenance_enabled,
      time_format: setting.time_format || "24h",
      yt_dlp_update_policy: setting.yt_dlp_update_policy || "stable",
      yt_dlp_pinned_version: setting.yt_dlp_pinned_version,
      podcast_url_base: setting.podcast_url_base,
      video_codec_preference: setting.video_codec_preference,
      audio_codec_preference: setting.audio_codec_preference
    })
  end

  defp assign_saved_fields(socket, setting, fields) do
    Enum.reduce(fields, socket, fn field, acc -> assign(acc, field, Map.get(setting, field)) end)
  end

  defp reflect_submitted(socket, attrs) do
    Enum.reduce(attrs, socket, fn {key, value}, acc ->
      assign(acc, String.to_existing_atom(key), value)
    end)
  end

  defp field_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp test_api_key(keys_string) when keys_string in [nil, ""], do: {:error, "No API key provided"}

  defp test_api_key(keys_string) do
    keys =
      keys_string
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case keys do
      [] ->
        {:error, "No API key provided"}

      keys ->
        # Test every key so a bad key beyond the first (which is still used at
        # indexing time via round-robin) is caught here too.
        failed_indexes =
          keys
          |> Enum.with_index(1)
          |> Enum.filter(fn {key, _index} -> match?({:error, _}, youtube_api().test_api_key(key)) end)
          |> Enum.map(fn {_key, index} -> index end)

        case failed_indexes do
          [] -> :ok
          [index] -> {:error, "Key #{index} failed"}
          indexes -> {:error, "Keys #{Enum.join(indexes, ", ")} failed"}
        end
    end
  end

  defp blank?(value), do: value in [nil, ""] or String.trim(to_string(value)) == ""

  defp apprise_runner, do: Application.get_env(:pinchflat, :apprise_runner)
  defp youtube_api, do: Application.get_env(:pinchflat, :youtube_api, Pinchflat.FastIndexing.YoutubeApi)
end
