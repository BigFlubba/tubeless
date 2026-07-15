> [!TIP]
> This is a community-maintained fork of [kieraneglin/pinchflat](https://github.com/kieraneglin/pinchflat). The original project is not actively maintained; this fork exists to continue development and apply community contributions. See [Migrating from kieraneglin/pinchflat](#migrating-from-kieraneglinpinchflat). PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Discord Server [created](https://discord.gg/7jdBJGCrq)!

> [!IMPORTANT]
> **Volunteers needed:** I started this GitHub org with the intent of providing life support to valuable but unmaintained open-source projects, hoping we could build a small community around it. Tubeless is Elixir/Phoenix, so that's directly useful here, but the org's needs go beyond any one stack — Docker/GHCR image publishing, GitHub Actions/CI maintenance, release management, issue triage, and documentation all help regardless of what project we take on next. If you're interested in joining or bringing another project in, let me know what you'd like to work on and any relevant experience you have.

<p align="center">
  <img
    src="priv/static/images/logo-white-wordmark-with-background.png"
    width="700"
  />
</p>

<div align="center">

[![](https://img.shields.io/github/v/release/CommunityMaintained/tubeless?style=for-the-badge&color=purple)](https://github.com/CommunityMaintained/tubeless/releases)
[![](https://img.shields.io/static/v1?style=for-the-badge&logo=discord&message=Chat&color=5865F2&label=Discord)](https://discord.gg/7jdBJGCrq)
[![](https://img.shields.io/github/actions/workflow/status/CommunityMaintained/tubeless/release-please.yml?style=for-the-badge)](https://github.com/CommunityMaintained/tubeless/actions/workflows/release-please.yml)
[![](https://img.shields.io/github/license/CommunityMaintained/tubeless?style=for-the-badge&color=ee512b)](LICENSE)

</div>

# Your next YouTube media manager

## Table of contents:

- [Your next YouTube media manager](#your-next-youtube-media-manager)
  - [Table of contents:](#table-of-contents)
  - [What it does](#what-it-does)
  - [Features](#features)
  - [Screenshots](#screenshots)
  - [Installation](#installation)
    - [Unraid](#unraid)
    - [Portainer](#portainer)
    - [Docker](#docker)
    - [Podman](#podman)
    - [IMPORTANT: File permissions](#important-file-permissions)
    - [ADVANCED: Storing Tubeless config directory on a network share](#advanced-storing-tubeless-config-directory-on-a-network-share)
    - [Environment variables](#environment-variables)
    - [Reverse Proxies](#reverse-proxies)
      - [Caddy Proxy Example](#caddy-proxy-example)
  - [Migrating from kieraneglin/pinchflat](#migrating-from-kieraneglinpinchflat)
  - [Stability disclaimer](#stability-disclaimer)
  - [Legal Use \& Disclaimer](#legal-use--disclaimer)
  - [License](#license)

## What it does

Tubeless is a self-hosted app for downloading YouTube content built using [yt-dlp](https://github.com/yt-dlp/yt-dlp). It's designed to be lightweight, self-contained, and easy to use. You set up rules for how to download content from YouTube channels or playlists and it'll do the rest, periodically checking for new content. It's perfect for people who want to download content for use with a media center app (Plex, Jellyfin, Kodi) or for those who want to archive media!

While you can [download individual videos](https://github.com/CommunityMaintained/tubeless/wiki/Frequently-Asked-Questions#how-do-i-download-one-off-videos), Tubeless is best suited for downloading content from channels or playlists. It's also not meant for consuming content in-app - Tubeless downloads content to disk where you can then watch it with a media center app or VLC.

If it doesn't work for your use case, please make a feature request! You can also check out these great alternatives: [Tube Archivist](https://github.com/tubearchivist/tubearchivist), [ytdl-sub](https://github.com/jmbannon/ytdl-sub), and [TubeSync](https://github.com/meeb/tubesync)

## Features

- Self-contained - just one Docker container with no external dependencies
- Powerful naming system so content is stored where and how you want it
- Easy-to-use web interface with presets to get you started right away
- First-class support for media center apps like Plex, Jellyfin, and Kodi ([docs](https://github.com/CommunityMaintained/tubeless/wiki/Frequently-Asked-Questions#how-do-i-get-media-into-plexjellyfinkodi))
- Supports serving RSS feeds to your favourite podcast app ([docs](https://github.com/CommunityMaintained/tubeless/wiki/Podcast-RSS-Feeds))
- Automatically downloads new content from channels and playlists
  - Uses a novel approach to download new content more quickly than other apps
- Supports downloading audio content
- Custom rules for handling YouTube Shorts and livestreams
- Apprise support for notifications
- Allows automatically redownloading new media after a set period
  - This can help improve the download quality of new content or improve SponsorBlock tags
- Optionally automatically delete old content ([docs](https://github.com/CommunityMaintained/tubeless/wiki/Automatically-Delete-Media))
- Advanced options like setting cutoff dates and filtering by title ([docs](https://github.com/CommunityMaintained/tubeless/wiki/Frequently-Asked-Questions#i-only-want-certain-videos-from-a-source---how-can-i-only-download-those))
- Reliable hands-off operation
- Can pass cookies to YouTube to download your private playlists ([docs](https://github.com/CommunityMaintained/tubeless/wiki/YouTube-Cookies))
- Sponsorblock integration
- \[Advanced\] control how `yt-dlp` updates from Settings - track stable or nightly, pin an exact version, or temporarily ride nightly and auto-return to stable once the fix lands there
- \[Advanced\] allows custom `yt-dlp` options ([docs](https://github.com/CommunityMaintained/tubeless/wiki/%5BAdvanced%5D-Custom-yt%E2%80%90dlp-options))
- \[Advanced\] supports running custom scripts after downloading/deleting media (alpha - [docs](https://github.com/CommunityMaintained/tubeless/wiki/%5BAdvanced%5D-Custom-lifecycle-scripts))

## Screenshots

<img src="priv/static/images/app-form-screenshot.jpg" alt="Tubeless screenshot" width="700" />
<img src="priv/static/images/app-screenshot.jpg" alt="Tubeless screenshot" width="700" />

## Installation

### Unraid

~~Simply search for Tubeless in the Community Apps store!~~

- Currently unavailable.

### Portainer

> [!IMPORTANT]
> See the note below about storing config on a network file share. It's preferred to store the config on a local disk if at all possible.

Docker Compose file:

```yaml
services:
  tubeless:
    image: ghcr.io/communitymaintained/tubeless:latest
    environment:
      # Set the timezone to your local timezone
      - TZ=America/New_York
    ports:
      - '8945:8945'
    volumes:
      - /host/path/to/config:/config
      - /host/path/to/downloads:/downloads
```

### Docker

1. Create two directories on your host machine: one for storing config and one for storing downloaded media. Make sure they're both writable by the user running the Docker container.
2. Prepare the docker image in one of the two ways below:
   - **From GHCR:** `docker pull ghcr.io/communitymaintained/tubeless:latest`
     - NOTE: also available on Docker Hub at `communitymaintained/tubeless:latest`
   - **Building locally:** `docker build . --file docker/selfhosted.Dockerfile -t ghcr.io/communitymaintained/tubeless:latest`
3. Run the container:

```bash
# Be sure to replace /host/path/to/config and /host/path/to/downloads below with
# the paths to the directories you created in step 1
# Be sure to replace America/New_York with your local timezone
docker run \
  -e TZ=America/New_York \
  -p 8945:8945 \
  -v /host/path/to/config:/config \
  -v /host/path/to/downloads:/downloads \
  ghcr.io/communitymaintained/tubeless:latest
```

### Podman

The Podman setup is similar to Docker but changes a few flags to run under a User Namespace instead of root. To run Tubeless under Podman and use the current user's UID/GID for file access run this:

```
podman run \
  --security-opt label=disable \
  --userns=keep-id --user=$UID \
  -e TZ=America/Los_Angeles \
  -p 8945:8945 \
  -v /host/path/to/config:/config:rw \
  -v /host/path/to/downloads/:/downloads:rw \
  ghcr.io/communitymaintained/tubeless:latest
```

Using this setup consider creating a new `tubeless` user and giving that user ownership to the config and download directory. See [Podman --userns](https://docs.podman.io/en/v4.6.1/markdown/options/userns.container.html) docs.

### IMPORTANT: File permissions

You _must_ ensure the host directories you've mounted are writable by the user running the Docker container. If you get a permission error follow the steps it suggests. See [upstream #106](https://github.com/kieraneglin/pinchflat/issues/106) for more.

> [!IMPORTANT]
> It's not recommended to run the container as root. Doing so can create permission issues if other apps need to work with the downloaded media.

### ADVANCED: Storing Tubeless config directory on a network share

As pointed out in [upstream #137](https://github.com/kieraneglin/pinchflat/issues/137), SQLite doesn't like being run in WAL mode on network shares. If you're running Tubeless on a network share, you can disable WAL mode by setting the `JOURNAL_MODE` environment variable to `delete`. This will make Tubeless run in rollback journal mode which is less performant but should work on network shares.

> [!CAUTION]
> Changing this setting from WAL to `delete` on an existing Tubeless instance could, conceivably, result in data loss. Only change this setting if you know what you're doing, why this is important, and are okay with possible data loss or DB corruption. Backup your database first!

If you change this setting and it works well for you, please open an issue or leave a comment on [upstream #137](https://github.com/kieraneglin/pinchflat/issues/137)! Doubly so if it does _not_ work well.

### Environment variables

| Name                        | Required? | Default                        | Notes                                                                                                                                            |
| --------------------------- | --------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `TZ`                        | No        | `UTC`                          | Must follow IANA TZ format                                                                                                                       |
| `LOG_LEVEL`                 | No        | `debug`                        | Can be set to `info` but `debug` is strongly recommended                                                                                         |
| `UMASK`                     | No        | `022`                          | Unraid users may want to set this to `000`                                                                                                       |
| `BASIC_AUTH_USERNAME`       | No        |                                | See [authentication docs](https://github.com/CommunityMaintained/tubeless/wiki/Username-and-Password)                                            |
| `BASIC_AUTH_PASSWORD`       | No        |                                | See [authentication docs](https://github.com/CommunityMaintained/tubeless/wiki/Username-and-Password)                                            |
| `EXPOSE_FEED_ENDPOINTS`     | No        | `false`                        | See [RSS feed docs](https://github.com/CommunityMaintained/tubeless/wiki/Podcast-RSS-Feeds)                                                      |
| `ENABLE_IPV6`               | No        | `false`                        | Setting to _any_ non-blank value will enable IPv6                                                                                                |
| `JOURNAL_MODE`              | No        | `wal`                          | Set to `delete` if your config directory is stored on a network share (not recommended)                                                          |
| `TZ_DATA_PATH`              | No        | `<EXTRAS_PATH>/elixir_tz_data` | The container path where the timezone database is stored                                                                                         |
| `BASE_ROUTE_PATH`           | No        | `/`                            | The base path for route generation. Useful when running behind certain reverse proxies - prefixes must be stripped.                              |
| `YT_DLP_WORKER_CONCURRENCY` | No        | `2`                            | The number of concurrent workers that use `yt-dlp` _per queue_. Set to 1 if you're getting IP limited, otherwise don't touch it                  |
| `ENABLE_PROMETHEUS`         | No        | `false`                        | Setting to _any_ non-blank value will enable Prometheus. See [docs](https://github.com/CommunityMaintained/tubeless/wiki/Prometheus-and-Grafana) |

### Reverse Proxies

Tubeless makes heavy use of websockets for real-time updates. If you're running Tubeless behind a reverse proxy then you'll need to make sure it's configured to support websockets.

#### Caddy Proxy Example

To configure Tubeless behind Caddy set the `BASE_ROUTE_PATH` environment variable to `/tubeless/` then add a stanza like this to the `Caddyfile`:

```caddyfile
home.example.com:443 {
  redir /tubeless /tubeless/

  handle_path /tubeless/* {
    reverse_proxy localhost:8945
  }
}
```

## Migrating from kieraneglin/pinchflat

The data format is identical — no database changes are needed. Just update the image reference in your Docker run command or compose file:

```text
ghcr.io/kieraneglin/pinchflat:latest  →  ghcr.io/communitymaintained/tubeless:latest
```

Also available on Docker Hub as `communitymaintained/tubeless:latest`.

Stop the old container, update the image reference, and start it again. Your `/config` and `/downloads` volumes carry over unchanged.

---

## Stability disclaimer

This software is in active development and anything can break at any time. I make no guarantees about the stability of this software, forward-compatibility of updates, or integrity (both related to and independent of Tubeless).

## Legal Use & Disclaimer

This project is intended **only** for downloading and managing content you have the legal right to access and copy (e.g., your own uploads, public‑domain works, or content licensed for download). You are responsible for complying with copyright law, platform terms of service, and any applicable regulations.

**Not legal advice.** This repository provides software only. It is not affiliated with YouTube, Plex, Jellyfin, or any other platform. The authors and contributors do not endorse or encourage unauthorized copying, circumvention of access controls, or other unlawful use.

If you plan to use this project publicly, make sure your usage and documentation do **not** promote or facilitate infringement or bypass of technical protection measures.

## License

See [LICENSE](LICENSE) file
