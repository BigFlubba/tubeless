# Third-Party Notices

Tubeless bundles or invokes the following third-party software. Each remains subject to its own license; the AGPL-3.0 applies to Tubeless's own source only.

| Component                                                 | License                                                         | Role                                                                              | Source                                  |
| --------------------------------------------------------- | --------------------------------------------------------------- | --------------------------------------------------------------------------------- | --------------------------------------- |
| yt-dlp                                                    | Unlicense                                                       | Invoked as an external program; a pinned build is included in the container image | https://github.com/yt-dlp/yt-dlp        |
| ffmpeg / ffprobe                                          | GPL-3.0-or-later (see below — the shipped build is a GPL build) | Invoked as external programs for muxing/transcoding                               | https://ffmpeg.org                      |
| Deno                                                      | MIT                                                             | Invoked by yt-dlp for certain YouTube downloads (yt-dlp#14404)                    | https://github.com/denoland/deno        |
| Apprise                                                   | BSD-2-Clause                                                    | Invoked as an external program to dispatch notifications                          | https://github.com/caronc/apprise       |
| SQLean                                                    | MIT                                                             | SQLite extensions loaded at runtime                                               | https://github.com/nalgeon/sqlean       |
| Elixir/Erlang, Phoenix, Oban, and other dependencies      | see `mix.lock`                                                  | Compiled dependencies                                                             | https://hex.pm                          |
| Alpine.js, Tailwind CSS, esbuild, Heroicons, Simple Icons | see `assets/yarn.lock` and `mix.lock`                           | Frontend dependencies compiled into the served assets                             | https://www.npmjs.com                   |
| Satoshi                                                   | Fontshare free-for-commercial-use license                       | Self-hosted webfont in `priv/static/fonts/`                                       | https://www.fontshare.com/fonts/satoshi |

## ffmpeg: build configuration and corresponding source

The published images ship a **GPL build** of ffmpeg — it is configured with `--enable-gpl --enable-version3`, so the resulting binaries are covered by **GPL-3.0-or-later**, not LGPL. Distributing the Tubeless container image therefore conveys GPL binaries, and the corresponding source must be made available; it is linked below.

The binary is not built by this project. It is a prebuilt artifact downloaded in `docker/ci-base.Dockerfile` from [yt-dlp/FFmpeg-Builds](https://github.com/yt-dlp/FFmpeg-Builds) and copied into the release image by `docker/selfhosted.Dockerfile`.

## Trademarks

YouTube and Google are trademarks of Google LLC; Plex is a trademark of Plex, Inc.; Jellyfin and Kodi are trademarks of their respective projects. Tubeless is not affiliated with, endorsed by, or sponsored by any of them, and uses these names only for identification and interoperability.
