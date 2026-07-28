defmodule Pinchflat.Repo.Migrations.AddProxySettings do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      # One of "none" | "manual" | "file". "manual" uses proxy_url; "file" picks
      # a random proxy from /config/extras/proxy.json per yt-dlp invocation
      add :proxy_mode, :string, default: "none", null: false
      # The single proxy URL used when proxy_mode == "manual"
      add :proxy_url, :string, null: true
      # When true, Tubeless's own RSS + YouTube Data API HTTP calls are also
      # routed through the proxy (not just yt-dlp). Off by default
      add :proxy_covers_http, :boolean, default: false, null: false
    end
  end
end
