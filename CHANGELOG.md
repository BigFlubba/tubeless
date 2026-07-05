# Changelog

## [1.3.1](https://github.com/CommunityMaintained/pinchflat/compare/v1.3.0...v1.3.1) (2026-07-05)


### Bug Fixes

* auto-refresh Media History on job state changes ([98d654f](https://github.com/CommunityMaintained/pinchflat/commit/98d654fb32736da9948bb1d11ccdf94c43aed537))
* correct static Size values in sources table on re-sort ([a876bcd](https://github.com/CommunityMaintained/pinchflat/commit/a876bcd817847a87e44bbbc9f50b366202186b0a)), closes [#112](https://github.com/CommunityMaintained/pinchflat/issues/112)
* handle unparseable yt-dlp source metadata responses gracefully ([813c8ad](https://github.com/CommunityMaintained/pinchflat/commit/813c8adcda43a6885dde19b4e2496526810417f8))
* index channel tabs separately so new shorts are found on repeat indexes ([13a160a](https://github.com/CommunityMaintained/pinchflat/commit/13a160a0a8b84d2c0f7b7214e73ba305acb58365)), closes [#59](https://github.com/CommunityMaintained/pinchflat/issues/59)
* label binary byte sizes with IEC units eg. KiB/MiB/GiB ([47fde1f](https://github.com/CommunityMaintained/pinchflat/commit/47fde1f81a992d4b0c8d7634a4c11ba6075330a1))
* unlock-pro modal button stuck disabled ([#125](https://github.com/CommunityMaintained/pinchflat/issues/125)) ([5c26116](https://github.com/CommunityMaintained/pinchflat/commit/5c261160f79ea9fccaea8cafd3096d1954ddd1c0))
* warn on malformed output-path templates in the UI ([c4bb94a](https://github.com/CommunityMaintained/pinchflat/commit/c4bb94a0f7af07023d295e8bd9f7a990ab9aa376))


### Chores

* add local CI lint/test script ([6b5bc79](https://github.com/CommunityMaintained/pinchflat/commit/6b5bc7926e3037a70417714548db9f05a13e5463))
* **ci:** bump ci-base image to sha-93af908 ([6d29a27](https://github.com/CommunityMaintained/pinchflat/commit/6d29a276522c034fdf6f824a14e096431488ff35))
* **ci:** fetch sqlean extensions at build time instead of vendoring ([053064b](https://github.com/CommunityMaintained/pinchflat/commit/053064b8d6abe262a96131715240020da92f2600))
* **ci:** release config updates ([4bf8cf2](https://github.com/CommunityMaintained/pinchflat/commit/4bf8cf26ea3620eb1330b30cf6afba8ba74a8dad))
* **deps:** update actions/cache action to v6 ([271b43b](https://github.com/CommunityMaintained/pinchflat/commit/271b43b1de7de7926c7c78636ca590e802d00d80))
* **deps:** update github actions ([8003703](https://github.com/CommunityMaintained/pinchflat/commit/800370390b385ba5f65b3b5b060d7c49429d5cf4))
* **deps:** update to 2026-07-01-16-32 ffmpeg build ([93af908](https://github.com/CommunityMaintained/pinchflat/commit/93af908ee245665899331600b464d6f88e462f28))
* **deps:** use published faker instead of private git fork ([792da4a](https://github.com/CommunityMaintained/pinchflat/commit/792da4abc49c7e55b58081cb10fedbf4f4e57a03))
* track ci-base pip requirements with Renovate ([8f1194d](https://github.com/CommunityMaintained/pinchflat/commit/8f1194dc50d0484f9bd6fe944e86ed77d039064c))


### Documentation

* clarify metadata/NFO toggle labels in media profile form ([7680d06](https://github.com/CommunityMaintained/pinchflat/commit/7680d065ddd5ccb66adf49d03c3a86580110fcb6))
* update README ([2d2d141](https://github.com/CommunityMaintained/pinchflat/commit/2d2d1416656922f5629172922d40516a8853a9bf))

## [1.3.0](https://github.com/CommunityMaintained/pinchflat/compare/v1.2.0...v1.3.0) (2026-06-30)


### Features

* add queue visibility and discarded job management to diagnostics ([5343985](https://github.com/CommunityMaintained/pinchflat/commit/5343985e6614d448cd0e3b1e56e78569be008800))
* control yt-dlp update behavior from settings ([058ba47](https://github.com/CommunityMaintained/pinchflat/commit/058ba4762a5415246cf73f4e68cddda68bc1f295))


### Bug Fixes

* avoid length/1 check and reformat mix.exs deps ([4d3986a](https://github.com/CommunityMaintained/pinchflat/commit/4d3986acfee4a5762f2357518b2db6f1008b1e87))
* configure Oban PG notifier and incomplete unique states for 2.23 ([0fb0183](https://github.com/CommunityMaintained/pinchflat/commit/0fb018302e699e106c5c8d0e552e3c69b08509b6))
* keep indexing reschedule from deduping against its own executing job ([115f8db](https://github.com/CommunityMaintained/pinchflat/commit/115f8db8ef6e6b1a7edf72844536a8ade2f9e0a1))
* pin Deno and Apprise in selfhosted runner to match ci-base ([b9b372c](https://github.com/CommunityMaintained/pinchflat/commit/b9b372cbabf956fd4eabecf82de6c843cda7cae4))
* resolve Elixir 1.20 compiler warnings ([43ea35d](https://github.com/CommunityMaintained/pinchflat/commit/43ea35dcf9ee8ef8b73ddd861b16326230af4320))
* route ecto.migrate ERD guard through sh for Elixir 1.20 ([04cf3f3](https://github.com/CommunityMaintained/pinchflat/commit/04cf3f3ccfac71f5c8f17472b8eba20ca54d8439))
* update formatting for phoenix ([cd6cc8b](https://github.com/CommunityMaintained/pinchflat/commit/cd6cc8b542ac405074ed773dc34314bdc3d89300))


### Reverts

* Move Active Tasks to tab in Media History section ([#836](https://github.com/CommunityMaintained/pinchflat/issues/836)) ([59849e3](https://github.com/CommunityMaintained/pinchflat/commit/59849e342817d1961feb147c6c0b0aa325a993e3))


### Chores

* add tooling script ([460fbd1](https://github.com/CommunityMaintained/pinchflat/commit/460fbd1c6ce7783bbae8932ed64ee24ea4325a2e))
* **ci:** run lint/test jobs natively in ci-base container ([e5430f2](https://github.com/CommunityMaintained/pinchflat/commit/e5430f2a96cf58bc13f7ea8d904b8ffe86ab963b))
* **deps:** alpinejs 3.15.12 ([a12f722](https://github.com/CommunityMaintained/pinchflat/commit/a12f72252945aa5fcb50f7f2af77c470aaacd64b))
* **deps:** bump Elixir 1.20.2, OTP 28.5.0.2, Debian trixie-20260623 in ci-base ([95b825a](https://github.com/CommunityMaintained/pinchflat/commit/95b825afc7bf93dc96d469f30252d6db0157bd48))
* **deps:** bump Node 20 -&gt; 24 in ci-base, add renovate tracking, sync CODEBASE versions ([f22adc4](https://github.com/CommunityMaintained/pinchflat/commit/f22adc49c18a5734476dee61165b3496368e4501))
* **deps:** faker to work with elixir 1.20; update misc deps ([edbff35](https://github.com/CommunityMaintained/pinchflat/commit/edbff3587d58f72023e4685e114f1700d7fbbe50))
* **deps:** pin dependencies ([e002b75](https://github.com/CommunityMaintained/pinchflat/commit/e002b7547bf9f374069a7983d79b0d68d541aaa8))
* **deps:** pin elixir in renovate ([cb55b03](https://github.com/CommunityMaintained/pinchflat/commit/cb55b0300e14b513e86374e199f9787415e21731))
* **deps:** replace floki with lazy_html ([13d7924](https://github.com/CommunityMaintained/pinchflat/commit/13d79242daf9b7a16a4358ccf82369d4a38782a7))
* **deps:** update dependency alpinejs to v3.15.12 ([a753ff8](https://github.com/CommunityMaintained/pinchflat/commit/a753ff8f4cd2535ce0a216b58c9e2f248b007801))
* **deps:** update dependency exqlite to 0.38.0 ([6e2dc17](https://github.com/CommunityMaintained/pinchflat/commit/6e2dc17dc7d0b7dcfbcff8d15fce4228713180d6))
* **deps:** update dependency phoenix to ~&gt; 1.8.0 ([9c0f74d](https://github.com/CommunityMaintained/pinchflat/commit/9c0f74dcdcc53059a86a4639eff7ef6aee440bd9))
* **deps:** update dependency phoenix_live_view to v1.2.4 ([a239149](https://github.com/CommunityMaintained/pinchflat/commit/a2391491ece970bb80fb15ecc87d14c75624ac41))
* **deps:** update dependency phoenix_live_view to v1.2.5 ([b2d638e](https://github.com/CommunityMaintained/pinchflat/commit/b2d638e6016be4fbd97211354e18e5b2213214f8))
* **deps:** update dependency prettier to v3.8.5 ([9389279](https://github.com/CommunityMaintained/pinchflat/commit/93892793013fe284804494867fe81a38fa99c3ea))
* **deps:** update dependency prettier to v3.9.0 ([2e9301a](https://github.com/CommunityMaintained/pinchflat/commit/2e9301a1bd3f4430a1ad53cea9aa74f318aae252))
* **deps:** update dependency prettier to v3.9.1 ([a66decb](https://github.com/CommunityMaintained/pinchflat/commit/a66decb323fe6c1480a18f0f1fe20bcaf96dbaa8))
* **deps:** update dependency prettier to v3.9.3 ([8130c84](https://github.com/CommunityMaintained/pinchflat/commit/8130c84d5372f3f56210bdb8c4480447041864f5))
* **deps:** update dependency prettier to v3.9.4 ([d2c4d45](https://github.com/CommunityMaintained/pinchflat/commit/d2c4d45215b4874fdbdd6321a9f3317e6aaf4ade))
* **deps:** update dependency tailwind to ~&gt; 0.5.0 ([9e38148](https://github.com/CommunityMaintained/pinchflat/commit/9e38148d894629d3deb52e95935dcc69564e6d57))
* **deps:** update phoenix_live_view ([e0651b6](https://github.com/CommunityMaintained/pinchflat/commit/e0651b68765431dcb5bdfde5ec6463b41d545e24))
* **deps:** update renovate constraints ([7051c58](https://github.com/CommunityMaintained/pinchflat/commit/7051c58c92809767826639f5ad9bcf6f2ac7ea19))
* **deps:** update timex digest to 3.7.13 ([e4f9983](https://github.com/CommunityMaintained/pinchflat/commit/e4f99831d2540f7cf98e05d68daea740b1f1c1b1))
* **deps:** update timex digest to 5ad1b82 ([83710dc](https://github.com/CommunityMaintained/pinchflat/commit/83710dcb75b88ede0e97451883424bc6d8920665))
* **deps:** use new elixir/otp ([f5e830b](https://github.com/CommunityMaintained/pinchflat/commit/f5e830b97a7e553c3660e14f93d8b76316b98b1a))
* schedule renovate biweekly, remove PR rate limits, enable dependency dashboard ([efe8668](https://github.com/CommunityMaintained/pinchflat/commit/efe8668216c4070ad443935958157f8466f9f6b5))
* tune release-please changelog sections ([5e1fa12](https://github.com/CommunityMaintained/pinchflat/commit/5e1fa12cb63113ac3a283d0b8f4b07ac483e9b78))


### Documentation

* reference yt-dlp faq ([80529fc](https://github.com/CommunityMaintained/pinchflat/commit/80529fc7d3b32dcc831e5918ebf7029f66932792))

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
