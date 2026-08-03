defmodule Pinchflat.Repo.Migrations.AddTableDensitySetting do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      # Row spacing used when rendering data tables in the UI: "compact" | "normal".
      # Purely a display preference, so it's a user choice rather than derived from
      # anything in the environment. Defaults to "compact" (the tighter spacing)
      add :table_density, :string, default: "compact", null: false
    end
  end
end
