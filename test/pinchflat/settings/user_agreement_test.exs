defmodule Pinchflat.Settings.UserAgreementTest do
  use Pinchflat.DataCase

  alias Pinchflat.Settings
  alias Pinchflat.Settings.UserAgreement

  describe "version/0 and effective_date/0" do
    test "are read from the version line in DISCLAIMER.md" do
      assert UserAgreement.version() =~ ~r/^\d+\.\d+$/
      assert UserAgreement.effective_date() =~ ~r/^\d{4}-\d{2}-\d{2}$/
    end
  end

  describe "markdown/0" do
    test "is the text of DISCLAIMER.md" do
      assert UserAgreement.markdown() =~ "## 6. Disclaimer of warranties"
    end

    test "drops the title and version line, which the agreement page renders itself" do
      refute UserAgreement.markdown() =~ "# Tubeless"
      refute UserAgreement.markdown() =~ "effective #{UserAgreement.effective_date()}"
    end
  end

  describe "accepted?/0" do
    test "is false when the agreement has never been accepted" do
      refute UserAgreement.accepted?()
    end

    test "is true once the current version has been accepted" do
      assert {:ok, _} = UserAgreement.accept()
      assert UserAgreement.accepted?()
    end

    test "is false when a different version was accepted" do
      Settings.set(agreement_accepted_version: "some-old-version")

      refute UserAgreement.accepted?()
    end
  end

  describe "accepted_before?/0" do
    test "is false when nothing has ever been accepted" do
      refute UserAgreement.accepted_before?()
    end

    test "is true when an older version was accepted" do
      Settings.set(agreement_accepted_version: "some-old-version")

      assert UserAgreement.accepted_before?()
    end
  end

  describe "accept/0" do
    test "records the current version and the time of acceptance" do
      assert {:ok, _} = UserAgreement.accept()

      assert Settings.get!(:agreement_accepted_version) == UserAgreement.version()
      assert %DateTime{} = UserAgreement.accepted_at()
    end
  end
end
