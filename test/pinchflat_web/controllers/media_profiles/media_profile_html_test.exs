defmodule PinchflatWeb.MediaProfiles.MediaProfileHTMLTest do
  use Pinchflat.DataCase

  import Pinchflat.ProfilesFixtures

  alias PinchflatWeb.MediaProfiles.MediaProfileHTML

  defp fields_for(media_profile, group_title) do
    media_profile
    |> MediaProfileHTML.info_groups()
    |> Enum.find(&(&1.title == group_title))
    |> Map.fetch!(:fields)
    |> Map.new(&{&1.label, &1.value})
  end

  describe "info_groups/1" do
    test "every field is a display-ready string or nil" do
      media_profile = media_profile_fixture()

      for group <- MediaProfileHTML.info_groups(media_profile),
          info_field <- group.fields do
        assert is_binary(info_field.value) or is_nil(info_field.value)
        assert is_binary(info_field.label)
        assert is_binary(info_field.help)
      end
    end

    test "renders booleans as Yes and No rather than raw values" do
      media_profile = media_profile_fixture(%{download_nfo: true, download_thumbnail: false})

      assert %{"Download NFO" => "Yes", "Download thumbnail" => "No"} = fields_for(media_profile, "Extra files")
    end

    test "uses the friendly resolution label and defaults the container" do
      media_profile = media_profile_fixture(%{preferred_resolution: :"2160p", media_container: nil})

      assert %{"Preferred resolution" => "4K", "Container" => "mp4 (default)"} = fields_for(media_profile, "Quality")
    end

    test "names SponsorBlock categories in plain language" do
      media_profile =
        media_profile_fixture(%{
          sponsorblock_remove_categories: ["sponsor", "music_offtopic"],
          sponsorblock_mark_categories: []
        })

      fields = fields_for(media_profile, "SponsorBlock")

      assert fields["Removed segments"] == "Sponsor, Non-music Section"
      # An empty list is "unset" so it hides behind the toggle rather than reading as "[]"
      assert fields["Marked segments"] == nil
    end

    test "summarizes what the profile downloads consistently with the index table" do
      media_profile = media_profile_fixture(%{shorts_behaviour: :only, livestream_behaviour: :exclude})

      assert %{"Downloads" => "Shorts only", "Shorts" => "Only"} = fields_for(media_profile, "Content")
    end
  end

  describe "field_set?/1" do
    test "treats blank and nil values as unset" do
      refute MediaProfileHTML.field_set?(%{value: nil})
      refute MediaProfileHTML.field_set?(%{value: "  "})
      assert MediaProfileHTML.field_set?(%{value: "No"})
    end
  end

  describe "effective_output_path/1" do
    test "joins the profile's template to the media directory a download really uses" do
      media_profile = media_profile_fixture(%{output_path_template: "/{{ title }}.{{ ext }}"})
      media_directory = Application.get_env(:pinchflat, :media_directory)

      {path, note} = MediaProfileHTML.effective_output_path(media_profile)

      assert path == Path.join(media_directory, "/{{ title }}.{{ ext }}")
      assert is_nil(note)
    end

    test "returns the podcast library layout and explains why for podcast profiles" do
      media_profile = media_profile_fixture(%{podcast_enabled: true, output_path_template: "/ignored.{{ ext }}"})

      {path, note} = MediaProfileHTML.effective_output_path(media_profile)

      refute path =~ "ignored"
      assert path =~ "source_slug"
      assert note =~ "ignore the output path template"
    end
  end

  describe "output_path_override_count/2" do
    test "counts only sources that actually set an override" do
      sources = [
        %{output_path_template_override: "/elsewhere/{{ title }}.{{ ext }}"},
        %{output_path_template_override: nil},
        %{output_path_template_override: "   "}
      ]

      assert MediaProfileHTML.output_path_override_count(media_profile_fixture(), sources) == 1
    end

    test "is zero when no source overrides the profile" do
      assert MediaProfileHTML.output_path_override_count(media_profile_fixture(), []) == 0
    end

    # Sources.output_path_template/1 checks podcast? before the override, so a
    # podcast source downloads into the podcast library regardless of what its
    # override says - counting it would claim it downloads somewhere it doesn't
    test "ignores overrides on a podcast profile, which never honours them" do
      media_profile = media_profile_fixture(%{podcast_enabled: true})
      sources = [%{output_path_template_override: "/elsewhere/{{ title }}.{{ ext }}"}]

      assert MediaProfileHTML.output_path_override_count(media_profile, sources) == 0
    end
  end

  describe "yt_dlp_option_lines/1" do
    test "renders flags with values and bare flags alike" do
      media_profile = media_profile_fixture(%{download_metadata: true, preferred_resolution: :"1080p"})
      lines = MediaProfileHTML.yt_dlp_option_lines(media_profile)

      assert "--write-info-json" in lines
      assert "--remux-video mp4" in lines
      assert Enum.any?(lines, &String.starts_with?(&1, "--format "))
    end

    test "omits flags the profile doesn't enable" do
      media_profile = media_profile_fixture(%{download_subs: false, embed_subs: false, download_nfo: false})
      lines = MediaProfileHTML.yt_dlp_option_lines(media_profile)

      refute "--write-subs" in lines
      refute Enum.any?(lines, &String.starts_with?(&1, "--sponsorblock"))
    end

    test "includes the sponsorblock flags when categories are set" do
      media_profile = media_profile_fixture(%{sponsorblock_remove_categories: ["sponsor", "intro"]})

      assert "--sponsorblock-remove sponsor,intro" in MediaProfileHTML.yt_dlp_option_lines(media_profile)
    end
  end

  describe "source_status_pill/2" do
    test "reports a disabled source as paused regardless of job health" do
      assert %{label: "Paused"} = MediaProfileHTML.source_status_pill(%{id: 1, enabled: false}, MapSet.new([1]))
    end

    test "reports a source in the failing set as an error" do
      assert %{label: "Error"} = MediaProfileHTML.source_status_pill(%{id: 1, enabled: true}, MapSet.new([1]))
    end

    test "reports everything else as active" do
      assert %{label: "Active"} = MediaProfileHTML.source_status_pill(%{id: 1, enabled: true}, MapSet.new([2]))
    end
  end
end
