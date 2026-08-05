# Contributing to Tubeless

## Background

Pinchflat was created by [@kieraneglin](https://github.com/kieraneglin) and grew a dedicated community of self-hosters. When the original project became unmaintained, a fork has been created to keep it alive — applying backlogged PRs, fixing bugs, and perhaps continuing development.

This repo is community-run. There is no single owner; contributions from anyone are welcome.

## How to contribute

### Responsible Use

By contributing, you agree not to add features or documentation that encourage:

- Unauthorized copying of copyrighted content
- Circumvention of access controls, DRM, or paywalls
- Misrepresentation of platform affiliation or endorsement

### Scope limits

We do not accept contributions that implement, assist, or document circumvention of technological protection measures, DRM decryption, defeat of authentication or payment controls, age-verification bypass, or evasion of anti-automation measures. Pull requests and issues of this kind will be closed without discussion. This is a hard scope boundary, not a matter of implementation quality.

### Reporting bugs and requesting features

Open an issue. Check for duplicates first. For bugs, include your Docker version, logs, and steps to reproduce.

### Submitting code

1. Fork the repo and create a branch from `main`.
2. Make your changes. If you're adding a feature, consider opening an issue first to discuss it.
3. Commit using [Conventional Commits](https://www.conventionalcommits.org/) — this drives automatic versioning:
   - `fix: ...` → patch release
   - `feat: ...` → minor release
   - `chore: ...` / `docs: ...` → no release bump
4. Open a PR against `main`. CI will run tests and build a Docker image tagged `pr-<number>-<sha>` for testing.
5. A maintainer will review and merge.

### Developer Certificate of Origin

All commits must be signed off (`git commit -s`), certifying the [Developer Certificate of Origin 1.1](https://developercertificate.org/). By signing off you certify that you wrote the contribution or have the right to submit it under the project's AGPL-3.0 license, and that you are not submitting code copied from a source with incompatible terms.

### Development setup

TBA

## Release process

Releases are managed automatically by [release-please](https://github.com/googleapis/release-please). When PRs are merged to `main`, release-please maintains a running Release PR that tracks the next version. Merging that PR cuts a release, publishes a GitHub Release, and pushes versioned Docker images to GHCR and Docker Hub.
