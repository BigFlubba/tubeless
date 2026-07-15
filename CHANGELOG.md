# Changelog

## 0.0.1 (2026-07-15)


### ⚠ BREAKING CHANGES

* bump major version for first release

### Features

* Add queue diagnostics page ([#48](https://github.com/CommunityMaintained/tubeless/issues/48)) ([578f698](https://github.com/CommunityMaintained/tubeless/commit/578f698712339bcb5ad3186fb39db0618286cbac))
* add queue visibility and discarded job management to diagnostics ([5343985](https://github.com/CommunityMaintained/tubeless/commit/5343985e6614d448cd0e3b1e56e78569be008800))
* add release-please, change versioning to SemVer ([67c85f3](https://github.com/CommunityMaintained/tubeless/commit/67c85f314d25d49d60205b600da5b791ff314332))
* add setting to ignore unavailable/members-only media ([eff8c0c](https://github.com/CommunityMaintained/tubeless/commit/eff8c0c075b287fbee19fbbcbc7a2ad234a27b64))
* Add YouTube API key testing in Settings ([#47](https://github.com/CommunityMaintained/tubeless/issues/47)) ([90303c1](https://github.com/CommunityMaintained/tubeless/commit/90303c15108a45f22c4fffbd31f15a99ade1f24c))
* bump major version for first release ([1bedbe4](https://github.com/CommunityMaintained/tubeless/commit/1bedbe4c1bd6edab107af5e529b03f2df4ecb2b6))
* bump release ([914dbd3](https://github.com/CommunityMaintained/tubeless/commit/914dbd3c1f0caea4e3238a64a4ad4b7df424c5c2))
* control yt-dlp update behavior from settings ([058ba47](https://github.com/CommunityMaintained/tubeless/commit/058ba4762a5415246cf73f4e68cddda68bc1f295))
* let templates mark where channel artwork and NFOs are stored ([279bebf](https://github.com/CommunityMaintained/tubeless/commit/279bebfdc8ce1f3fa4f6d69f772c58ea356c6ac9))
* mask YouTube API key and add cookies file management ([#53](https://github.com/CommunityMaintained/tubeless/issues/53)) ([343a630](https://github.com/CommunityMaintained/tubeless/commit/343a630638bdf099a786e9022e3f3f6daf712a92))
* rebrand user-facing product name to Tubeless ([739d82a](https://github.com/CommunityMaintained/tubeless/commit/739d82a3665566cec21f60daaec1b7890321d3f0))
* report accurate status for non-downloaded media in Other tab ([8c188ac](https://github.com/CommunityMaintained/tubeless/commit/8c188aca346a873e31ee2b8296c3e20f09615cf9))
* requeue stuck jobs from the Diagnostics page instead of cancelling them ([cbabc68](https://github.com/CommunityMaintained/tubeless/commit/cbabc68414a12ee4c42acecec62c6e0fe08e5cba))
* surface auto-skipped unavailable media as a distinct status ([e88d403](https://github.com/CommunityMaintained/tubeless/commit/e88d403c4d3b655ee08b5785298313e3fb6f3df8))


### Bug Fixes

* assigng correct tags to dev builds ([36709df](https://github.com/CommunityMaintained/tubeless/commit/36709df589050e2f2787d505c43f551872ca6c9b))
* auto-refresh Media History on job state changes ([98d654f](https://github.com/CommunityMaintained/tubeless/commit/98d654fb32736da9948bb1d11ccdf94c43aed537))
* avoid length/1 check and reformat mix.exs deps ([4d3986a](https://github.com/CommunityMaintained/tubeless/commit/4d3986acfee4a5762f2357518b2db6f1008b1e87))
* **ci:** correct casing for ghcr ([e08570b](https://github.com/CommunityMaintained/tubeless/commit/e08570bb7d50fa9df6e372459d0cb58f64f1b7a5))
* **ci:** correct job deps in release ([a03f71a](https://github.com/CommunityMaintained/tubeless/commit/a03f71acb8172b6944fb4ef65d81b5eb414eebd9))
* **ci:** ignore prettier in changelog ([de54801](https://github.com/CommunityMaintained/tubeless/commit/de548018f7d17e1c2db6d7e8d466ea4de24e9f83))
* **ci:** remove CalVer, build version needs to be semver compliant ([55dece8](https://github.com/CommunityMaintained/tubeless/commit/55dece8e63f77520e3a55d1a587415d7661b2b3d))
* configure Oban PG notifier and incomplete unique states for 2.23 ([0fb0183](https://github.com/CommunityMaintained/tubeless/commit/0fb018302e699e106c5c8d0e552e3c69b08509b6))
* correct pending count for sources with no downloaded media ([8675262](https://github.com/CommunityMaintained/tubeless/commit/8675262eebc7dad00f229d850fad9f50d3b09ef1))
* correct static Size values in sources table on re-sort ([a876bcd](https://github.com/CommunityMaintained/tubeless/commit/a876bcd817847a87e44bbbc9f50b366202186b0a)), closes [#112](https://github.com/CommunityMaintained/tubeless/issues/112)
* handle suffix Range requests and missing files when streaming media ([e4c5a32](https://github.com/CommunityMaintained/tubeless/commit/e4c5a3293f7c6cf4fc5e3d13324e8cc27f0606d5))
* handle unparseable yt-dlp source metadata responses gracefully ([813c8ad](https://github.com/CommunityMaintained/tubeless/commit/813c8adcda43a6885dde19b4e2496526810417f8))
* index channel tabs separately so new shorts are found on repeat indexes ([13a160a](https://github.com/CommunityMaintained/tubeless/commit/13a160a0a8b84d2c0f7b7214e73ba305acb58365)), closes [#59](https://github.com/CommunityMaintained/tubeless/issues/59)
* keep indexing reschedule from deduping against its own executing job ([115f8db](https://github.com/CommunityMaintained/tubeless/commit/115f8db8ef6e6b1a7edf72844536a8ade2f9e0a1))
* label binary byte sizes with IEC units eg. KiB/MiB/GiB ([47fde1f](https://github.com/CommunityMaintained/tubeless/commit/47fde1f81a992d4b0c8d7634a4c11ba6075330a1))
* linter ([7b29408](https://github.com/CommunityMaintained/tubeless/commit/7b29408165bfca80d6c0c344dd275a1c880fd799))
* pin Deno and Apprise in selfhosted runner to match ci-base ([b9b372c](https://github.com/CommunityMaintained/tubeless/commit/b9b372cbabf956fd4eabecf82de6c843cda7cae4))
* prettier'd new code ([ba41fb2](https://github.com/CommunityMaintained/tubeless/commit/ba41fb22cd5f954d9033efcfec4c94838be8c462))
* re-download existing media by forcing the download job ([f47a6e0](https://github.com/CommunityMaintained/tubeless/commit/f47a6e03e2780cc67b6646560410085adb90e453))
* reflect new github org in webui ([2b8faeb](https://github.com/CommunityMaintained/tubeless/commit/2b8faeb29f342cc2d4382f0caee0add8a0046dbd))
* render NFO aired date as plain date for Jellyfin ([#60](https://github.com/CommunityMaintained/tubeless/issues/60)) ([0282c19](https://github.com/CommunityMaintained/tubeless/commit/0282c19789d3154bf4eff92a74c8d7c90186ba5f)), closes [#57](https://github.com/CommunityMaintained/tubeless/issues/57)
* reschedule missing source indexing jobs on boot ([beb6a16](https://github.com/CommunityMaintained/tubeless/commit/beb6a16ea25a94e9c68d9560bba035debaa5e113))
* resolve Elixir 1.20 compiler warnings ([43ea35d](https://github.com/CommunityMaintained/tubeless/commit/43ea35dcf9ee8ef8b73ddd861b16326230af4320))
* restore the media search box after a LiveView reconnect ([c447d21](https://github.com/CommunityMaintained/tubeless/commit/c447d21d413fd64875c91a47228ea5b9559fdce6))
* route ecto.migrate ERD guard through sh for Elixir 1.20 ([04cf3f3](https://github.com/CommunityMaintained/tubeless/commit/04cf3f3ccfac71f5c8f17472b8eba20ca54d8439))
* serve apple-touch-icon to avoid 404 probes from iOS ([451123b](https://github.com/CommunityMaintained/tubeless/commit/451123b108bf2dfa14c6b87577a261f4c739d0f3))
* skip download archive when the archive file cannot be written ([5aac447](https://github.com/CommunityMaintained/tubeless/commit/5aac4477f36d291b27045434eedf6aaf8f08e246))
* stop crashing when rendering 404 and 500 error pages ([#154](https://github.com/CommunityMaintained/tubeless/issues/154)) ([7b0bd7f](https://github.com/CommunityMaintained/tubeless/commit/7b0bd7f37668a6428172a471c843d6a582cebb36))
* stop logging YouTube API keys ([515eabf](https://github.com/CommunityMaintained/tubeless/commit/515eabf1a5a59abffe32c2d18ffc98c47ab1e222))
* stop losing in-flight source enable toggles on LiveView reconnect ([6d9d184](https://github.com/CommunityMaintained/tubeless/commit/6d9d184d9d973ffa4fbda4d16d8e4d268018cff2))
* stop the diagnostics page crashing when job queues aren't running ([779080c](https://github.com/CommunityMaintained/tubeless/commit/779080c20b1ee0809bbdd770bc3f82fc7002633c))
* test all YouTube API keys and report which fail ([347f0be](https://github.com/CommunityMaintained/tubeless/commit/347f0be760933ac546766f24bed689f475d69d6f))
* throttle job state broadcasts to reduce dashboard query load ([21555ae](https://github.com/CommunityMaintained/tubeless/commit/21555aef88e33be75b0af3e7ec374a9483a5f2c9))
* unlock-pro modal button stuck disabled ([#125](https://github.com/CommunityMaintained/tubeless/issues/125)) ([5c26116](https://github.com/CommunityMaintained/tubeless/commit/5c261160f79ea9fccaea8cafd3096d1954ddd1c0))
* update formatting for phoenix ([cd6cc8b](https://github.com/CommunityMaintained/tubeless/commit/cd6cc8b542ac405074ed773dc34314bdc3d89300))
* update image name ([122503d](https://github.com/CommunityMaintained/tubeless/commit/122503de2f03d1c57eb7d117b3ae88928f028538))
* warn on malformed output-path templates in the UI ([c4bb94a](https://github.com/CommunityMaintained/tubeless/commit/c4bb94a0f7af07023d295e8bd9f7a990ab9aa376))


### Reverts

* Move Active Tasks to tab in Media History section ([#836](https://github.com/CommunityMaintained/tubeless/issues/836)) ([59849e3](https://github.com/CommunityMaintained/tubeless/commit/59849e342817d1961feb147c6c0b0aa325a993e3))


### Chores

* add fast Docker test runner for local iteration ([b976cf2](https://github.com/CommunityMaintained/tubeless/commit/b976cf2aad014fc6fb43ee9a97a15b57daa18b12))
* add local CI lint/test script ([6b5bc79](https://github.com/CommunityMaintained/tubeless/commit/6b5bc7926e3037a70417714548db9f05a13e5463))
* add sqlite to final image ([c1cbdb2](https://github.com/CommunityMaintained/tubeless/commit/c1cbdb2c7ad112e7fd1f44634ff7246c8262c89e))
* add tooling script ([460fbd1](https://github.com/CommunityMaintained/tubeless/commit/460fbd1c6ce7783bbae8932ed64ee24ea4325a2e))
* bump sqleton ([6ecadf7](https://github.com/CommunityMaintained/tubeless/commit/6ecadf74edc09fdd580f5d36110365313588070f))
* **ci:** bump ci-base image to sha-93af908 ([6d29a27](https://github.com/CommunityMaintained/tubeless/commit/6d29a276522c034fdf6f824a14e096431488ff35))
* **ci:** bump ci-base image to sha-ba3e559 ([a13ac24](https://github.com/CommunityMaintained/tubeless/commit/a13ac24d9a81d804234bd024b4a789c793bb0492))
* **ci:** fetch sqlean extensions at build time instead of vendoring ([053064b](https://github.com/CommunityMaintained/tubeless/commit/053064b8d6abe262a96131715240020da92f2600))
* **ci:** release config updates ([4bf8cf2](https://github.com/CommunityMaintained/tubeless/commit/4bf8cf26ea3620eb1330b30cf6afba8ba74a8dad))
* **ci:** run lint/test jobs natively in ci-base container ([e5430f2](https://github.com/CommunityMaintained/tubeless/commit/e5430f2a96cf58bc13f7ea8d904b8ffe86ab963b))
* **ci:** track hexpm/elixir base image versions with Renovate ([ba3e559](https://github.com/CommunityMaintained/tubeless/commit/ba3e559ec54cc2e925312e0cec3ee07e18bf88a0))
* **ci:** use main as default branch ([ea68a7c](https://github.com/CommunityMaintained/tubeless/commit/ea68a7c0daa1c9bb0e7ebead34a9c1e9112997df))
* **ci:** use new ci image ([1dc9b2b](https://github.com/CommunityMaintained/tubeless/commit/1dc9b2b467a91cb564ae1f6985f187be6ce08bbe))
* clarify migration paths ([7ac7551](https://github.com/CommunityMaintained/tubeless/commit/7ac755108ae88d3c7407068dd13aaf07c6284bb3))
* **deps:** alpinejs 3.15.12 ([a12f722](https://github.com/CommunityMaintained/tubeless/commit/a12f72252945aa5fcb50f7f2af77c470aaacd64b))
* **deps:** bump Elixir 1.20.2, OTP 28.5.0.2, Debian trixie-20260623 in ci-base ([95b825a](https://github.com/CommunityMaintained/tubeless/commit/95b825afc7bf93dc96d469f30252d6db0157bd48))
* **deps:** bump Erlang/OTP to 28.5.0.3 ([cf681a2](https://github.com/CommunityMaintained/tubeless/commit/cf681a2962a6247aab5ceafd3e003d7df2db697c))
* **deps:** bump Node 20 -&gt; 24 in ci-base, add renovate tracking, sync CODEBASE versions ([f22adc4](https://github.com/CommunityMaintained/tubeless/commit/f22adc49c18a5734476dee61165b3496368e4501))
* **deps:** faker to work with elixir 1.20; update misc deps ([edbff35](https://github.com/CommunityMaintained/tubeless/commit/edbff3587d58f72023e4685e114f1700d7fbbe50))
* **deps:** pin dependencies ([e002b75](https://github.com/CommunityMaintained/tubeless/commit/e002b7547bf9f374069a7983d79b0d68d541aaa8))
* **deps:** pin elixir in renovate ([cb55b03](https://github.com/CommunityMaintained/tubeless/commit/cb55b0300e14b513e86374e199f9787415e21731))
* **deps:** replace floki with lazy_html ([13d7924](https://github.com/CommunityMaintained/tubeless/commit/13d79242daf9b7a16a4358ccf82369d4a38782a7))
* **deps:** tighten ecto_sqlite3 and prom_ex constraints and bump locked deps ([768b120](https://github.com/CommunityMaintained/tubeless/commit/768b12051b0578d92e06d36e464af0779e60e842))
* **deps:** update actions/cache action to v6 ([271b43b](https://github.com/CommunityMaintained/tubeless/commit/271b43b1de7de7926c7c78636ca590e802d00d80))
* **deps:** update dependency alpinejs to v3.15.12 ([a753ff8](https://github.com/CommunityMaintained/tubeless/commit/a753ff8f4cd2535ce0a216b58c9e2f248b007801))
* **deps:** update dependency apprise to v1.12.0 ([945105b](https://github.com/CommunityMaintained/tubeless/commit/945105be5544cfd911b161d560cebac010b91b46))
* **deps:** update dependency exqlite to 0.38.0 ([6e2dc17](https://github.com/CommunityMaintained/tubeless/commit/6e2dc17dc7d0b7dcfbcff8d15fce4228713180d6))
* **deps:** update dependency phoenix to ~&gt; 1.8.0 ([9c0f74d](https://github.com/CommunityMaintained/tubeless/commit/9c0f74dcdcc53059a86a4639eff7ef6aee440bd9))
* **deps:** update dependency phoenix_live_view to v1.2.4 ([a239149](https://github.com/CommunityMaintained/tubeless/commit/a2391491ece970bb80fb15ecc87d14c75624ac41))
* **deps:** update dependency phoenix_live_view to v1.2.5 ([b2d638e](https://github.com/CommunityMaintained/tubeless/commit/b2d638e6016be4fbd97211354e18e5b2213214f8))
* **deps:** update dependency prettier to v3.8.4 ([cd0456d](https://github.com/CommunityMaintained/tubeless/commit/cd0456de4ae71f4385c62d342086c043eabef421))
* **deps:** update dependency prettier to v3.8.5 ([9389279](https://github.com/CommunityMaintained/tubeless/commit/93892793013fe284804494867fe81a38fa99c3ea))
* **deps:** update dependency prettier to v3.9.0 ([2e9301a](https://github.com/CommunityMaintained/tubeless/commit/2e9301a1bd3f4430a1ad53cea9aa74f318aae252))
* **deps:** update dependency prettier to v3.9.1 ([a66decb](https://github.com/CommunityMaintained/tubeless/commit/a66decb323fe6c1480a18f0f1fe20bcaf96dbaa8))
* **deps:** update dependency prettier to v3.9.3 ([8130c84](https://github.com/CommunityMaintained/tubeless/commit/8130c84d5372f3f56210bdb8c4480447041864f5))
* **deps:** update dependency prettier to v3.9.4 ([d2c4d45](https://github.com/CommunityMaintained/tubeless/commit/d2c4d45215b4874fdbdd6321a9f3317e6aaf4ade))
* **deps:** update dependency prettier to v3.9.5 ([a6359e0](https://github.com/CommunityMaintained/tubeless/commit/a6359e07f4d33fc5be75861e39d4546eee4744b2))
* **deps:** update dependency sobelow to ~&gt; 0.14 ([1bcaeeb](https://github.com/CommunityMaintained/tubeless/commit/1bcaeeb80d0086661726d2784a06ec770fd69326))
* **deps:** update dependency sqleton to v2.3.0 ([74ef149](https://github.com/CommunityMaintained/tubeless/commit/74ef149c7f7ac76cbed707188c84379a39bff742))
* **deps:** update dependency sqleton to v4 ([3143550](https://github.com/CommunityMaintained/tubeless/commit/31435505b4cd892f23a7bbeba4ad646f6a82b0bc))
* **deps:** update dependency tailwind to ~&gt; 0.5.0 ([9e38148](https://github.com/CommunityMaintained/tubeless/commit/9e38148d894629d3deb52e95935dcc69564e6d57))
* **deps:** update github actions ([8003703](https://github.com/CommunityMaintained/tubeless/commit/800370390b385ba5f65b3b5b060d7c49429d5cf4))
* **deps:** update github actions ([c487511](https://github.com/CommunityMaintained/tubeless/commit/c487511b27d2efc3927edec026f752f049143f7d))
* **deps:** update github actions ([fa27ffe](https://github.com/CommunityMaintained/tubeless/commit/fa27ffefd790a351133be05cc413fe656cf07bab))
* **deps:** update github actions to v7 ([#52](https://github.com/CommunityMaintained/tubeless/issues/52)) ([7429586](https://github.com/CommunityMaintained/tubeless/commit/742958666e59b82e8b17710c9e3dfa6de36da3f3))
* **deps:** update phoenix_live_view ([e0651b6](https://github.com/CommunityMaintained/tubeless/commit/e0651b68765431dcb5bdfde5ec6463b41d545e24))
* **deps:** update renovate constraints ([7051c58](https://github.com/CommunityMaintained/tubeless/commit/7051c58c92809767826639f5ad9bcf6f2ac7ea19))
* **deps:** update timex digest to 3.7.13 ([e4f9983](https://github.com/CommunityMaintained/tubeless/commit/e4f99831d2540f7cf98e05d68daea740b1f1c1b1))
* **deps:** update timex digest to 5ad1b82 ([83710dc](https://github.com/CommunityMaintained/tubeless/commit/83710dcb75b88ede0e97451883424bc6d8920665))
* **deps:** update to 2026-07-01-16-32 ffmpeg build ([93af908](https://github.com/CommunityMaintained/tubeless/commit/93af908ee245665899331600b464d6f88e462f28))
* **deps:** use new elixir/otp ([f5e830b](https://github.com/CommunityMaintained/tubeless/commit/f5e830b97a7e553c3660e14f93d8b76316b98b1a))
* **deps:** use published faker instead of private git fork ([792da4a](https://github.com/CommunityMaintained/tubeless/commit/792da4abc49c7e55b58081cb10fedbf4f4e57a03))
* ignore runtime wiring and test support in coverage reporting ([a8f6d76](https://github.com/CommunityMaintained/tubeless/commit/a8f6d76d4da44a3c44ada129957daaa6090cc78b))
* **master:** release 1.0.0 ([5776d49](https://github.com/CommunityMaintained/tubeless/commit/5776d49c7d4bd343ab96eb563e0ad03579c5ebca))
* **master:** release 1.1.0 ([#26](https://github.com/CommunityMaintained/tubeless/issues/26)) ([9d4c7e6](https://github.com/CommunityMaintained/tubeless/commit/9d4c7e64a73e6b6486dd408bd849d0b2bee900c6))
* **master:** release 1.2.0 ([3f7ad33](https://github.com/CommunityMaintained/tubeless/commit/3f7ad33dacb2cf61b508ad940a9dd9a8f3da0484))
* move to debain trixie ([8103c96](https://github.com/CommunityMaintained/tubeless/commit/8103c9676f48f4605e7ed3bcd80104dc512f1fa8))
* prettify satoshi.css to pass lint ([067b4c1](https://github.com/CommunityMaintained/tubeless/commit/067b4c1bc806b6415d4ea11e982bbbe464fcbd18))
* schedule renovate biweekly, remove PR rate limits, enable dependency dashboard ([efe8668](https://github.com/CommunityMaintained/tubeless/commit/efe8668216c4070ad443935958157f8466f9f6b5))
* set app version to 1.0.0 (2026.6.14) [skip ci] ([ac12ace](https://github.com/CommunityMaintained/tubeless/commit/ac12ace16959ba823e978239999f726b0508ae9e))
* track ci-base pip requirements with Renovate ([8f1194d](https://github.com/CommunityMaintained/tubeless/commit/8f1194dc50d0484f9bd6fe944e86ed77d039064c))
* tune release-please changelog sections ([5e1fa12](https://github.com/CommunityMaintained/tubeless/commit/5e1fa12cb63113ac3a283d0b8f4b07ac483e9b78))
* update images ([77ab2e5](https://github.com/CommunityMaintained/tubeless/commit/77ab2e56942eaa6233110d0c21dbd0ab66ecf717))


### Documentation

* add Caddy config example ([2a476a0](https://github.com/CommunityMaintained/tubeless/commit/2a476a0e6bf723a54e922e21c41f79e817e33302))
* add CI instructions ([77119c5](https://github.com/CommunityMaintained/tubeless/commit/77119c5929389a390785fbe052901d16b93b4e16))
* add CONTRIBUTING.md ([a27f0d2](https://github.com/CommunityMaintained/tubeless/commit/a27f0d24f69fdc8fa3e4a2689c704272e929c2e5))
* add Discord link, legal use disclaimer, and responsible use guidelines ([b8e6b28](https://github.com/CommunityMaintained/tubeless/commit/b8e6b28c036a6c5eb46a27ec409a34e875827670))
* add shorts channel ([1b77e9d](https://github.com/CommunityMaintained/tubeless/commit/1b77e9d29cf2941dd7e6265ceec612ee4ecc9b7b))
* adopt project ([d96f211](https://github.com/CommunityMaintained/tubeless/commit/d96f2119ae78423a8f457cc3ff78cf7c5f8d001c))
* clarify metadata/NFO toggle labels in media profile form ([7680d06](https://github.com/CommunityMaintained/tubeless/commit/7680d065ddd5ccb66adf49d03c3a86580110fcb6))
* clarify migration steps ([bf9defa](https://github.com/CommunityMaintained/tubeless/commit/bf9defadc0c25e4c3c3da5d5ee93dc0f78f09b49))
* correct boot sequence responsibilities in CLAUDE.md ([241be98](https://github.com/CommunityMaintained/tubeless/commit/241be98e3c0584f151a5849007378712b11227bc))
* fix docker compose example ([c7d00f7](https://github.com/CommunityMaintained/tubeless/commit/c7d00f7177876b1f6d3834d1c7d6cd66659fb652))
* prettify ([6a13000](https://github.com/CommunityMaintained/tubeless/commit/6a1300073e1f6deab01b7232764ade0c6e481fce))
* reference yt-dlp faq ([80529fc](https://github.com/CommunityMaintained/tubeless/commit/80529fc7d3b32dcc831e5918ebf7029f66932792))
* update README ([2d2d141](https://github.com/CommunityMaintained/tubeless/commit/2d2d1416656922f5629172922d40516a8853a9bf))


### Refactors

* remove unused Sources.IndexTableLive module ([ba498c9](https://github.com/CommunityMaintained/tubeless/commit/ba498c9c227ce9ca8f3340fcbb07bc8bfb3dec2c))

## Changelog

## Changes originally released as Pinchflat fork

### Pinchflat 1.4.0 (2026-07-10)


#### Features

* let templates mark where channel artwork and NFOs are stored ([279bebf](https://github.com/CommunityMaintained/tubeless/commit/279bebfdc8ce1f3fa4f6d69f772c58ea356c6ac9))
* requeue stuck jobs from the Diagnostics page instead of cancelling them ([cbabc68](https://github.com/CommunityMaintained/tubeless/commit/cbabc68414a12ee4c42acecec62c6e0fe08e5cba))


#### Bug Fixes

* correct pending count for sources with no downloaded media ([8675262](https://github.com/CommunityMaintained/tubeless/commit/8675262eebc7dad00f229d850fad9f50d3b09ef1))
* handle suffix Range requests and missing files when streaming media ([e4c5a32](https://github.com/CommunityMaintained/tubeless/commit/e4c5a3293f7c6cf4fc5e3d13324e8cc27f0606d5))
* reschedule missing source indexing jobs on boot ([beb6a16](https://github.com/CommunityMaintained/tubeless/commit/beb6a16ea25a94e9c68d9560bba035debaa5e113))
* restore the media search box after a LiveView reconnect ([c447d21](https://github.com/CommunityMaintained/tubeless/commit/c447d21d413fd64875c91a47228ea5b9559fdce6))
* skip download archive when the archive file cannot be written ([5aac447](https://github.com/CommunityMaintained/tubeless/commit/5aac4477f36d291b27045434eedf6aaf8f08e246))
* stop crashing when rendering 404 and 500 error pages ([#154](https://github.com/CommunityMaintained/tubeless/issues/154)) ([7b0bd7f](https://github.com/CommunityMaintained/tubeless/commit/7b0bd7f37668a6428172a471c843d6a582cebb36))
* stop logging YouTube API keys ([515eabf](https://github.com/CommunityMaintained/tubeless/commit/515eabf1a5a59abffe32c2d18ffc98c47ab1e222))
* stop losing in-flight source enable toggles on LiveView reconnect ([6d9d184](https://github.com/CommunityMaintained/tubeless/commit/6d9d184d9d973ffa4fbda4d16d8e4d268018cff2))
* stop the diagnostics page crashing when job queues aren't running ([779080c](https://github.com/CommunityMaintained/tubeless/commit/779080c20b1ee0809bbdd770bc3f82fc7002633c))
* test all YouTube API keys and report which fail ([347f0be](https://github.com/CommunityMaintained/tubeless/commit/347f0be760933ac546766f24bed689f475d69d6f))
* throttle job state broadcasts to reduce dashboard query load ([21555ae](https://github.com/CommunityMaintained/tubeless/commit/21555aef88e33be75b0af3e7ec374a9483a5f2c9))


#### Chores

* add fast Docker test runner for local iteration ([b976cf2](https://github.com/CommunityMaintained/tubeless/commit/b976cf2aad014fc6fb43ee9a97a15b57daa18b12))
* **ci:** bump ci-base image to sha-ba3e559 ([a13ac24](https://github.com/CommunityMaintained/tubeless/commit/a13ac24d9a81d804234bd024b4a789c793bb0492))
* **ci:** track hexpm/elixir base image versions with Renovate ([ba3e559](https://github.com/CommunityMaintained/tubeless/commit/ba3e559ec54cc2e925312e0cec3ee07e18bf88a0))
* **deps:** bump Erlang/OTP to 28.5.0.3 ([cf681a2](https://github.com/CommunityMaintained/tubeless/commit/cf681a2962a6247aab5ceafd3e003d7df2db697c))
* **deps:** update dependency apprise to v1.12.0 ([945105b](https://github.com/CommunityMaintained/tubeless/commit/945105be5544cfd911b161d560cebac010b91b46))
* ignore runtime wiring and test support in coverage reporting ([a8f6d76](https://github.com/CommunityMaintained/tubeless/commit/a8f6d76d4da44a3c44ada129957daaa6090cc78b))


#### Documentation

* correct boot sequence responsibilities in CLAUDE.md ([241be98](https://github.com/CommunityMaintained/tubeless/commit/241be98e3c0584f151a5849007378712b11227bc))


#### Refactors

* remove unused Sources.IndexTableLive module ([ba498c9](https://github.com/CommunityMaintained/tubeless/commit/ba498c9c227ce9ca8f3340fcbb07bc8bfb3dec2c))

### Pinchflat 1.3.1 (2026-07-05)


#### Bug Fixes

* auto-refresh Media History on job state changes ([98d654f](https://github.com/CommunityMaintained/tubeless/commit/98d654fb32736da9948bb1d11ccdf94c43aed537))
* correct static Size values in sources table on re-sort ([a876bcd](https://github.com/CommunityMaintained/tubeless/commit/a876bcd817847a87e44bbbc9f50b366202186b0a)), closes [#112](https://github.com/CommunityMaintained/tubeless/issues/112)
* handle unparseable yt-dlp source metadata responses gracefully ([813c8ad](https://github.com/CommunityMaintained/tubeless/commit/813c8adcda43a6885dde19b4e2496526810417f8))
* index channel tabs separately so new shorts are found on repeat indexes ([13a160a](https://github.com/CommunityMaintained/tubeless/commit/13a160a0a8b84d2c0f7b7214e73ba305acb58365)), closes [#59](https://github.com/CommunityMaintained/tubeless/issues/59)
* label binary byte sizes with IEC units eg. KiB/MiB/GiB ([47fde1f](https://github.com/CommunityMaintained/tubeless/commit/47fde1f81a992d4b0c8d7634a4c11ba6075330a1))
* unlock-pro modal button stuck disabled ([#125](https://github.com/CommunityMaintained/tubeless/issues/125)) ([5c26116](https://github.com/CommunityMaintained/tubeless/commit/5c261160f79ea9fccaea8cafd3096d1954ddd1c0))
* warn on malformed output-path templates in the UI ([c4bb94a](https://github.com/CommunityMaintained/tubeless/commit/c4bb94a0f7af07023d295e8bd9f7a990ab9aa376))


#### Chores

* add local CI lint/test script ([6b5bc79](https://github.com/CommunityMaintained/tubeless/commit/6b5bc7926e3037a70417714548db9f05a13e5463))
* **ci:** bump ci-base image to sha-93af908 ([6d29a27](https://github.com/CommunityMaintained/tubeless/commit/6d29a276522c034fdf6f824a14e096431488ff35))
* **ci:** fetch sqlean extensions at build time instead of vendoring ([053064b](https://github.com/CommunityMaintained/tubeless/commit/053064b8d6abe262a96131715240020da92f2600))
* **ci:** release config updates ([4bf8cf2](https://github.com/CommunityMaintained/tubeless/commit/4bf8cf26ea3620eb1330b30cf6afba8ba74a8dad))
* **deps:** update actions/cache action to v6 ([271b43b](https://github.com/CommunityMaintained/tubeless/commit/271b43b1de7de7926c7c78636ca590e802d00d80))
* **deps:** update github actions ([8003703](https://github.com/CommunityMaintained/tubeless/commit/800370390b385ba5f65b3b5b060d7c49429d5cf4))
* **deps:** update to 2026-07-01-16-32 ffmpeg build ([93af908](https://github.com/CommunityMaintained/tubeless/commit/93af908ee245665899331600b464d6f88e462f28))
* **deps:** use published faker instead of private git fork ([792da4a](https://github.com/CommunityMaintained/tubeless/commit/792da4abc49c7e55b58081cb10fedbf4f4e57a03))
* track ci-base pip requirements with Renovate ([8f1194d](https://github.com/CommunityMaintained/tubeless/commit/8f1194dc50d0484f9bd6fe944e86ed77d039064c))


#### Documentation

* clarify metadata/NFO toggle labels in media profile form ([7680d06](https://github.com/CommunityMaintained/tubeless/commit/7680d065ddd5ccb66adf49d03c3a86580110fcb6))
* update README ([2d2d141](https://github.com/CommunityMaintained/tubeless/commit/2d2d1416656922f5629172922d40516a8853a9bf))

### Pinchflat 1.3.0 (2026-06-30)


#### Features

* add queue visibility and discarded job management to diagnostics ([5343985](https://github.com/CommunityMaintained/tubeless/commit/5343985e6614d448cd0e3b1e56e78569be008800))
* control yt-dlp update behavior from settings ([058ba47](https://github.com/CommunityMaintained/tubeless/commit/058ba4762a5415246cf73f4e68cddda68bc1f295))


#### Bug Fixes

* avoid length/1 check and reformat mix.exs deps ([4d3986a](https://github.com/CommunityMaintained/tubeless/commit/4d3986acfee4a5762f2357518b2db6f1008b1e87))
* configure Oban PG notifier and incomplete unique states for 2.23 ([0fb0183](https://github.com/CommunityMaintained/tubeless/commit/0fb018302e699e106c5c8d0e552e3c69b08509b6))
* keep indexing reschedule from deduping against its own executing job ([115f8db](https://github.com/CommunityMaintained/tubeless/commit/115f8db8ef6e6b1a7edf72844536a8ade2f9e0a1))
* pin Deno and Apprise in selfhosted runner to match ci-base ([b9b372c](https://github.com/CommunityMaintained/tubeless/commit/b9b372cbabf956fd4eabecf82de6c843cda7cae4))
* resolve Elixir 1.20 compiler warnings ([43ea35d](https://github.com/CommunityMaintained/tubeless/commit/43ea35dcf9ee8ef8b73ddd861b16326230af4320))
* route ecto.migrate ERD guard through sh for Elixir 1.20 ([04cf3f3](https://github.com/CommunityMaintained/tubeless/commit/04cf3f3ccfac71f5c8f17472b8eba20ca54d8439))
* update formatting for phoenix ([cd6cc8b](https://github.com/CommunityMaintained/tubeless/commit/cd6cc8b542ac405074ed773dc34314bdc3d89300))


#### Reverts

* Move Active Tasks to tab in Media History section ([#836](https://github.com/CommunityMaintained/tubeless/issues/836)) ([59849e3](https://github.com/CommunityMaintained/tubeless/commit/59849e342817d1961feb147c6c0b0aa325a993e3))


#### Chores

* add tooling script ([460fbd1](https://github.com/CommunityMaintained/tubeless/commit/460fbd1c6ce7783bbae8932ed64ee24ea4325a2e))
* **ci:** run lint/test jobs natively in ci-base container ([e5430f2](https://github.com/CommunityMaintained/tubeless/commit/e5430f2a96cf58bc13f7ea8d904b8ffe86ab963b))
* **deps:** alpinejs 3.15.12 ([a12f722](https://github.com/CommunityMaintained/tubeless/commit/a12f72252945aa5fcb50f7f2af77c470aaacd64b))
* **deps:** bump Elixir 1.20.2, OTP 28.5.0.2, Debian trixie-20260623 in ci-base ([95b825a](https://github.com/CommunityMaintained/tubeless/commit/95b825afc7bf93dc96d469f30252d6db0157bd48))
* **deps:** bump Node 20 -&gt; 24 in ci-base, add renovate tracking, sync CODEBASE versions ([f22adc4](https://github.com/CommunityMaintained/tubeless/commit/f22adc49c18a5734476dee61165b3496368e4501))
* **deps:** faker to work with elixir 1.20; update misc deps ([edbff35](https://github.com/CommunityMaintained/tubeless/commit/edbff3587d58f72023e4685e114f1700d7fbbe50))
* **deps:** pin dependencies ([e002b75](https://github.com/CommunityMaintained/tubeless/commit/e002b7547bf9f374069a7983d79b0d68d541aaa8))
* **deps:** pin elixir in renovate ([cb55b03](https://github.com/CommunityMaintained/tubeless/commit/cb55b0300e14b513e86374e199f9787415e21731))
* **deps:** replace floki with lazy_html ([13d7924](https://github.com/CommunityMaintained/tubeless/commit/13d79242daf9b7a16a4358ccf82369d4a38782a7))
* **deps:** update dependency alpinejs to v3.15.12 ([a753ff8](https://github.com/CommunityMaintained/tubeless/commit/a753ff8f4cd2535ce0a216b58c9e2f248b007801))
* **deps:** update dependency exqlite to 0.38.0 ([6e2dc17](https://github.com/CommunityMaintained/tubeless/commit/6e2dc17dc7d0b7dcfbcff8d15fce4228713180d6))
* **deps:** update dependency phoenix to ~&gt; 1.8.0 ([9c0f74d](https://github.com/CommunityMaintained/tubeless/commit/9c0f74dcdcc53059a86a4639eff7ef6aee440bd9))
* **deps:** update dependency phoenix_live_view to v1.2.4 ([a239149](https://github.com/CommunityMaintained/tubeless/commit/a2391491ece970bb80fb15ecc87d14c75624ac41))
* **deps:** update dependency phoenix_live_view to v1.2.5 ([b2d638e](https://github.com/CommunityMaintained/tubeless/commit/b2d638e6016be4fbd97211354e18e5b2213214f8))
* **deps:** update dependency prettier to v3.8.5 ([9389279](https://github.com/CommunityMaintained/tubeless/commit/93892793013fe284804494867fe81a38fa99c3ea))
* **deps:** update dependency prettier to v3.9.0 ([2e9301a](https://github.com/CommunityMaintained/tubeless/commit/2e9301a1bd3f4430a1ad53cea9aa74f318aae252))
* **deps:** update dependency prettier to v3.9.1 ([a66decb](https://github.com/CommunityMaintained/tubeless/commit/a66decb323fe6c1480a18f0f1fe20bcaf96dbaa8))
* **deps:** update dependency prettier to v3.9.3 ([8130c84](https://github.com/CommunityMaintained/tubeless/commit/8130c84d5372f3f56210bdb8c4480447041864f5))
* **deps:** update dependency prettier to v3.9.4 ([d2c4d45](https://github.com/CommunityMaintained/tubeless/commit/d2c4d45215b4874fdbdd6321a9f3317e6aaf4ade))
* **deps:** update dependency tailwind to ~&gt; 0.5.0 ([9e38148](https://github.com/CommunityMaintained/tubeless/commit/9e38148d894629d3deb52e95935dcc69564e6d57))
* **deps:** update phoenix_live_view ([e0651b6](https://github.com/CommunityMaintained/tubeless/commit/e0651b68765431dcb5bdfde5ec6463b41d545e24))
* **deps:** update renovate constraints ([7051c58](https://github.com/CommunityMaintained/tubeless/commit/7051c58c92809767826639f5ad9bcf6f2ac7ea19))
* **deps:** update timex digest to 3.7.13 ([e4f9983](https://github.com/CommunityMaintained/tubeless/commit/e4f99831d2540f7cf98e05d68daea740b1f1c1b1))
* **deps:** update timex digest to 5ad1b82 ([83710dc](https://github.com/CommunityMaintained/tubeless/commit/83710dcb75b88ede0e97451883424bc6d8920665))
* **deps:** use new elixir/otp ([f5e830b](https://github.com/CommunityMaintained/tubeless/commit/f5e830b97a7e553c3660e14f93d8b76316b98b1a))
* schedule renovate biweekly, remove PR rate limits, enable dependency dashboard ([efe8668](https://github.com/CommunityMaintained/tubeless/commit/efe8668216c4070ad443935958157f8466f9f6b5))
* tune release-please changelog sections ([5e1fa12](https://github.com/CommunityMaintained/tubeless/commit/5e1fa12cb63113ac3a283d0b8f4b07ac483e9b78))


#### Documentation

* reference yt-dlp faq ([80529fc](https://github.com/CommunityMaintained/tubeless/commit/80529fc7d3b32dcc831e5918ebf7029f66932792))

### Pinchflat 1.2.0 (2026-06-26)


#### Features

* add setting to ignore unavailable/members-only media ([eff8c0c](https://github.com/CommunityMaintained/tubeless/commit/eff8c0c075b287fbee19fbbcbc7a2ad234a27b64))
* mask YouTube API key and add cookies file management ([#53](https://github.com/CommunityMaintained/tubeless/issues/53)) ([343a630](https://github.com/CommunityMaintained/tubeless/commit/343a630638bdf099a786e9022e3f3f6daf712a92))
* report accurate status for non-downloaded media in Other tab ([8c188ac](https://github.com/CommunityMaintained/tubeless/commit/8c188aca346a873e31ee2b8296c3e20f09615cf9))
* surface auto-skipped unavailable media as a distinct status ([e88d403](https://github.com/CommunityMaintained/tubeless/commit/e88d403c4d3b655ee08b5785298313e3fb6f3df8))


#### Bug Fixes

* re-download existing media by forcing the download job ([f47a6e0](https://github.com/CommunityMaintained/tubeless/commit/f47a6e03e2780cc67b6646560410085adb90e453))
* render NFO aired date as plain date for Jellyfin ([#60](https://github.com/CommunityMaintained/tubeless/issues/60)) ([0282c19](https://github.com/CommunityMaintained/tubeless/commit/0282c19789d3154bf4eff92a74c8d7c90186ba5f)), closes [#57](https://github.com/CommunityMaintained/tubeless/issues/57)
* serve apple-touch-icon to avoid 404 probes from iOS ([451123b](https://github.com/CommunityMaintained/tubeless/commit/451123b108bf2dfa14c6b87577a261f4c739d0f3))

### Pinchflat 1.1.0 (2026-06-18)


#### Features

* Add queue diagnostics page ([#48](https://github.com/CommunityMaintained/tubeless/issues/48)) ([578f698](https://github.com/CommunityMaintained/tubeless/commit/578f698712339bcb5ad3186fb39db0618286cbac))
* Add YouTube API key testing in Settings ([#47](https://github.com/CommunityMaintained/tubeless/issues/47)) ([90303c1](https://github.com/CommunityMaintained/tubeless/commit/90303c15108a45f22c4fffbd31f15a99ade1f24c))


#### Bug Fixes

* **ci:** remove CalVer, build version needs to be semver compliant ([55dece8](https://github.com/CommunityMaintained/tubeless/commit/55dece8e63f77520e3a55d1a587415d7661b2b3d))

### Pinchflat 1.0.0 (2026-06-14)


#### ⚠ BREAKING CHANGES

* bump major version for first release

#### Features

* add release-please, change versioning to SemVer ([67c85f3](https://github.com/CommunityMaintained/tubeless/commit/67c85f314d25d49d60205b600da5b791ff314332))
* bump major version for first release ([1bedbe4](https://github.com/CommunityMaintained/tubeless/commit/1bedbe4c1bd6edab107af5e529b03f2df4ecb2b6))
* bump release ([914dbd3](https://github.com/CommunityMaintained/tubeless/commit/914dbd3c1f0caea4e3238a64a4ad4b7df424c5c2))


#### Bug Fixes

* assigng correct tags to dev builds ([36709df](https://github.com/CommunityMaintained/tubeless/commit/36709df589050e2f2787d505c43f551872ca6c9b))
* **ci:** correct casing for ghcr ([e08570b](https://github.com/CommunityMaintained/tubeless/commit/e08570bb7d50fa9df6e372459d0cb58f64f1b7a5))
* **ci:** correct job deps in release ([a03f71a](https://github.com/CommunityMaintained/tubeless/commit/a03f71acb8172b6944fb4ef65d81b5eb414eebd9))
* **ci:** ignore prettier in changelog ([de54801](https://github.com/CommunityMaintained/tubeless/commit/de548018f7d17e1c2db6d7e8d466ea4de24e9f83))
* linter ([7b29408](https://github.com/CommunityMaintained/tubeless/commit/7b29408165bfca80d6c0c344dd275a1c880fd799))
* prettier'd new code ([ba41fb2](https://github.com/CommunityMaintained/tubeless/commit/ba41fb22cd5f954d9033efcfec4c94838be8c462))
* reflect new github org in webui ([2b8faeb](https://github.com/CommunityMaintained/tubeless/commit/2b8faeb29f342cc2d4382f0caee0add8a0046dbd))
* update image name ([122503d](https://github.com/CommunityMaintained/tubeless/commit/122503de2f03d1c57eb7d117b3ae88928f028538))
