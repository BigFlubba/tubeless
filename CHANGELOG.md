# Changelog

## [1.2.0](https://github.com/CommunityMaintained/pinchflat/compare/v1.1.0...v1.2.0) (2026-06-26)


### Features

* add setting to ignore unavailable/members-only media ([eff8c0c](https://github.com/CommunityMaintained/pinchflat/commit/eff8c0c075b287fbee19fbbcbc7a2ad234a27b64))
* mask YouTube API key and add cookies file management ([#53](https://github.com/CommunityMaintained/pinchflat/issues/53)) ([343a630](https://github.com/CommunityMaintained/pinchflat/commit/343a630638bdf099a786e9022e3f3f6daf712a92))
* report accurate status for non-downloaded media in Other tab ([8c188ac](https://github.com/CommunityMaintained/pinchflat/commit/8c188aca346a873e31ee2b8296c3e20f09615cf9))
* surface auto-skipped unavailable media as a distinct status ([e88d403](https://github.com/CommunityMaintained/pinchflat/commit/e88d403c4d3b655ee08b5785298313e3fb6f3df8))


### Bug Fixes

* re-download existing media by forcing the download job ([f47a6e0](https://github.com/CommunityMaintained/pinchflat/commit/f47a6e03e2780cc67b6646560410085adb90e453))
* render NFO aired date as plain date for Jellyfin ([#60](https://github.com/CommunityMaintained/pinchflat/issues/60)) ([0282c19](https://github.com/CommunityMaintained/pinchflat/commit/0282c19789d3154bf4eff92a74c8d7c90186ba5f)), closes [#57](https://github.com/CommunityMaintained/pinchflat/issues/57)
* serve apple-touch-icon to avoid 404 probes from iOS ([451123b](https://github.com/CommunityMaintained/pinchflat/commit/451123b108bf2dfa14c6b87577a261f4c739d0f3))

## [1.1.0](https://github.com/CommunityMaintained/pinchflat/compare/v1.0.0...v1.1.0) (2026-06-18)


### Features

* Add queue diagnostics page ([#48](https://github.com/CommunityMaintained/pinchflat/issues/48)) ([578f698](https://github.com/CommunityMaintained/pinchflat/commit/578f698712339bcb5ad3186fb39db0618286cbac))
* Add YouTube API key testing in Settings ([#47](https://github.com/CommunityMaintained/pinchflat/issues/47)) ([90303c1](https://github.com/CommunityMaintained/pinchflat/commit/90303c15108a45f22c4fffbd31f15a99ade1f24c))


### Bug Fixes

* **ci:** remove CalVer, build version needs to be semver compliant ([55dece8](https://github.com/CommunityMaintained/pinchflat/commit/55dece8e63f77520e3a55d1a587415d7661b2b3d))

## [1.0.0](https://github.com/CommunityMaintained/pinchflat/compare/v0.9.9...v1.0.0) (2026-06-14)


### ⚠ BREAKING CHANGES

* bump major version for first release

### Features

* add release-please, change versioning to SemVer ([67c85f3](https://github.com/CommunityMaintained/pinchflat/commit/67c85f314d25d49d60205b600da5b791ff314332))
* bump major version for first release ([1bedbe4](https://github.com/CommunityMaintained/pinchflat/commit/1bedbe4c1bd6edab107af5e529b03f2df4ecb2b6))
* bump release ([914dbd3](https://github.com/CommunityMaintained/pinchflat/commit/914dbd3c1f0caea4e3238a64a4ad4b7df424c5c2))


### Bug Fixes

* assigng correct tags to dev builds ([36709df](https://github.com/CommunityMaintained/pinchflat/commit/36709df589050e2f2787d505c43f551872ca6c9b))
* **ci:** correct casing for ghcr ([e08570b](https://github.com/CommunityMaintained/pinchflat/commit/e08570bb7d50fa9df6e372459d0cb58f64f1b7a5))
* **ci:** correct job deps in release ([a03f71a](https://github.com/CommunityMaintained/pinchflat/commit/a03f71acb8172b6944fb4ef65d81b5eb414eebd9))
* **ci:** ignore prettier in changelog ([de54801](https://github.com/CommunityMaintained/pinchflat/commit/de548018f7d17e1c2db6d7e8d466ea4de24e9f83))
* linter ([7b29408](https://github.com/CommunityMaintained/pinchflat/commit/7b29408165bfca80d6c0c344dd275a1c880fd799))
* prettier'd new code ([ba41fb2](https://github.com/CommunityMaintained/pinchflat/commit/ba41fb22cd5f954d9033efcfec4c94838be8c462))
* reflect new github org in webui ([2b8faeb](https://github.com/CommunityMaintained/pinchflat/commit/2b8faeb29f342cc2d4382f0caee0add8a0046dbd))
* update image name ([122503d](https://github.com/CommunityMaintained/pinchflat/commit/122503de2f03d1c57eb7d117b3ae88928f028538))
