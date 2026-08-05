defmodule Pinchflat.Profiles do
  @moduledoc """
  The Profiles context.
  """

  import Ecto.Query, warn: false

  alias Pinchflat.Repo
  alias Pinchflat.Sources
  alias Pinchflat.Profiles.MediaProfile
  alias Pinchflat.Podcasts.PodcastExportWorker

  @doc """
  Gets a single media_profile.

  Returns %MediaProfile{}. Raises `Ecto.NoResultsError` if the Media profile does not exist.
  """
  def get_media_profile!(id), do: Repo.get!(MediaProfile, id)

  @doc """
  Creates a media_profile.

  Returns {:ok, %MediaProfile{}} | {:error, %Ecto.Changeset{}}
  """
  def create_media_profile(attrs) do
    %MediaProfile{}
    |> MediaProfile.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a media_profile.

  Returns {:ok, %MediaProfile{}} | {:error, %Ecto.Changeset{}}
  """
  def update_media_profile(%MediaProfile{} = media_profile, attrs) do
    changeset = MediaProfile.changeset(media_profile, attrs)

    case Repo.update(changeset) do
      {:ok, updated_media_profile} ->
        maybe_kickoff_podcast_exports(changeset, updated_media_profile)
        {:ok, updated_media_profile}

      err ->
        err
    end
  end

  @doc """
  Deletes a media_profile, all its sources, and all their media items.
  Can optionally delete the media files.

  Returns {:ok, %MediaProfile{}} | {:error, %Ecto.Changeset{}}
  """
  def delete_media_profile(%MediaProfile{} = media_profile, opts \\ []) do
    delete_files = Keyword.get(opts, :delete_files, false)

    media_profile
    |> Sources.list_sources_for()
    |> Enum.each(fn source ->
      Sources.delete_source(source, delete_files: delete_files)
    end)

    Repo.delete(media_profile)
  end

  # Toggling the profile's podcast publishing changes whether its sources
  # publish, so each needs a (debounced) export-or-prune run
  defp maybe_kickoff_podcast_exports(changeset, media_profile) do
    if Map.has_key?(changeset.changes, :podcast_enabled) do
      media_profile
      |> Sources.list_sources_for()
      |> Enum.each(&PodcastExportWorker.kickoff/1)
    end

    :ok
  end

  @doc """
  Returns `%Ecto.Changeset{}`
  """
  def change_media_profile(%MediaProfile{} = media_profile, attrs \\ %{}) do
    MediaProfile.changeset(media_profile, attrs)
  end
end
