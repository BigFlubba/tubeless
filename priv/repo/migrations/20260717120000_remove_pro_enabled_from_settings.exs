defmodule Pinchflat.Repo.Migrations.RemoveProEnabledFromSettings do
  use Ecto.Migration

  def up do
    alter table(:settings) do
      remove :pro_enabled
    end
  end

  def down do
    alter table(:settings) do
      add :pro_enabled, :boolean, default: false, null: false
    end
  end
end
