defmodule Pinchflat.Repo.Migrations.DropSettingsBackup do
  use Ecto.Migration

  def up do
    drop_if_exists table(:settings_backup)
  end

  def down do
    create table(:settings_backup) do
      add :name, :string, null: false
      add :value, :string, null: false
      add :datatype, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:settings_backup, [:name])
  end
end
