defmodule Pinchflat.Settings do
  @moduledoc """
  The Settings context.
  """
  import Ecto.Query, warn: false

  alias Pinchflat.Repo
  alias Pinchflat.Settings.Setting
  alias Pinchflat.Podcasts.PodcastSweepWorker

  @doc """
  Returns the only setting record. It _should_ be impossible
  to create or delete this record, so it's assertive about
  assuming it's the only one.

  Returns %Setting{}
  """
  def record do
    Setting
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Updates the setting record.

  Returns {:ok, %Setting{}} | {:error, %Ecto.Changeset{}}
  """
  def update_setting(%Setting{} = setting, attrs) do
    case setting |> Setting.changeset(attrs) |> Repo.update() do
      {:ok, updated_setting} ->
        maybe_reconcile_podcast_exports(setting, updated_setting)
        {:ok, updated_setting}

      err ->
        err
    end
  end

  @doc """
  Updates a setting, returning the new value.
  Is setup to take a keyword list argument so you
  can call it like `Settings.set(onboarding: true)`

  Returns {:ok, value} | {:error, :invalid_key} | {:error, %Ecto.Changeset{}}
  """
  def set([{attr, value}]) do
    record()
    |> update_setting(%{attr => value})
    |> case do
      {:ok, %{^attr => _}} -> {:ok, value}
      {:ok, _} -> {:error, :invalid_key}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Gets the value of a setting.

  Returns {:ok, value} | {:error, :invalid_key}
  """
  def get(name) do
    case Map.fetch(record(), name) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :invalid_key}
    end
  end

  @doc """
  Gets the value of a setting, raising if it doesn't exist.

  Returns value
  """
  def get!(name) do
    case get(name) do
      {:ok, value} -> value
      {:error, _} -> raise "Setting `#{name}` not found"
    end
  end

  @doc """
  Returns `%Ecto.Changeset{}`

  Has no production caller — the settings page saves via `update_setting/2` — but
  is the entry point the settings tests use to exercise `Setting.changeset/2`'s
  validations directly.
  """
  def change_setting(%Setting{} = setting, attrs \\ %{}) do
    Setting.changeset(setting, attrs)
  end

  # A change to the podcast URL base means every static feed needs regenerating
  # with links pointing at the new origin. Living in the context (rather than the
  # settings controller) means any caller of `update_setting/2` or `set/1`
  # triggers the reconcile, not just the settings form.
  defp maybe_reconcile_podcast_exports(old_setting, new_setting) do
    if old_setting.podcast_url_base != new_setting.podcast_url_base do
      PodcastSweepWorker.kickoff()
    end

    :ok
  end
end
