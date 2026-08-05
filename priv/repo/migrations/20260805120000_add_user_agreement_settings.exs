defmodule Pinchflat.Repo.Migrations.AddUserAgreementSettings do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      # The version of the user agreement that was accepted, and when. NULL means
      # it has never been accepted - the UI is gated until it is. Storing the
      # version (rather than a boolean) is what lets a later revision of the text
      # re-prompt everyone. See `Pinchflat.Settings.UserAgreement`
      add :agreement_accepted_version, :string
      add :agreement_accepted_at, :utc_datetime
    end
  end
end
