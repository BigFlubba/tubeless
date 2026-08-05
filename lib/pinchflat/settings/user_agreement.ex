defmodule Pinchflat.Settings.UserAgreement do
  @moduledoc """
  The user agreement that must be accepted before Tubeless' UI can be used.

  `DISCLAIMER.md` in the project root is the single source of truth: both the
  text shown in the app and the version it's tracked under are read from it at
  compile time, so the copy people read on GitHub and the copy they accept in
  the UI can't drift apart.

  Acceptance is recorded as the *version* that was accepted rather than a plain
  boolean, so revising the agreement re-prompts everyone: bump the
  `**Version X.Y - effective YYYY-MM-DD**` line at the top of `DISCLAIMER.md`
  and the next page load asks for acceptance again. Editing the text without
  bumping that line (fixing a typo, say) deliberately doesn't re-prompt anyone.
  """

  alias Pinchflat.Settings

  @agreement_path Path.expand("../../../DISCLAIMER.md", __DIR__)
  @external_resource @agreement_path

  @raw_agreement File.read!(@agreement_path)

  # Matches the version line the document declares itself with. The separator is
  # an em dash in the file; en dashes and plain hyphens are accepted too, so a
  # well-meaning editor swapping it doesn't fail the build. The `u` modifier is
  # required for the dashes to be matched as characters rather than bytes.
  @version_regex ~r/^\*\*Version\s+(?<version>[\w.]+)\s*[—–-]?\s*effective\s+(?<date>\d{4}-\d{2}-\d{2})\*\*\s*$/mu

  @version_info (case Regex.named_captures(@version_regex, @raw_agreement) do
                   %{"version" => version, "date" => date} ->
                     %{version: version, effective_date: date}

                   nil ->
                     raise """
                     Couldn't find a version line in #{@agreement_path}.

                     The user agreement page reads its version from a line that looks like:

                         **Version 1.0 — effective 2026-08-05**
                     """
                 end)

  # The title and version line are dropped because the agreement dialog renders
  # both itself, and the trailing horizontal rules are dropped because they only
  # separate the document from the end of the file.
  @markdown @raw_agreement
            |> String.replace(~r/\A\s*#[^\n]*\n/, "")
            |> String.replace(@version_regex, "")
            |> String.replace(~r/(\n+\s*-{3,}[ \t]*)+\s*\z/, "")
            |> String.trim()

  @doc """
  The version of the agreement currently shipped with the app, as declared by
  `DISCLAIMER.md`.

  Returns binary()
  """
  def version, do: @version_info.version

  @doc """
  The date the current version of the agreement took effect, as declared by
  `DISCLAIMER.md`.

  Returns binary()
  """
  def effective_date, do: @version_info.effective_date

  @doc """
  The agreement text as Markdown, minus the title and version line that the
  agreement page renders on its own.

  Returns binary()
  """
  def markdown, do: @markdown

  @doc """
  Whether the current version of the agreement has been accepted.

  Returns boolean()
  """
  def accepted? do
    Settings.get!(:agreement_accepted_version) == version()
  end

  @doc """
  Whether _any_ version of the agreement has been accepted before. Used to tell
  a first-run user apart from one being re-prompted by a new version.

  Returns boolean()
  """
  def accepted_before? do
    not is_nil(Settings.get!(:agreement_accepted_version))
  end

  @doc """
  When the agreement was last accepted, if ever.

  Returns DateTime.t() | nil
  """
  def accepted_at do
    Settings.get!(:agreement_accepted_at)
  end

  @doc """
  Records acceptance of the current version of the agreement.

  Returns {:ok, %Setting{}} | {:error, %Ecto.Changeset{}}
  """
  def accept do
    Settings.update_setting(Settings.record(), %{
      agreement_accepted_version: version(),
      agreement_accepted_at: DateTime.utc_now()
    })
  end
end
