# Changelog

## 1.0.0 (2026-04-05)


### Features

* add Amazon Linux 2023 support (x86_64 and aarch64) ([3f60202](https://github.com/jksy/setup-imagemagick/commit/3f6020223b806c04fccc48e953192547a0a2c405))
* add Amazon Linux 2023 support (x86_64 and aarch64) ([6b909bd](https://github.com/jksy/setup-imagemagick/commit/6b909bded418c23a9343b162672907d99a7beecd))
* implement setup-imagemagick composite action ([156f806](https://github.com/jksy/setup-imagemagick/commit/156f806ec6f557e3d39d787dbf8c1496bfb9e86a))
* install ghostscript within setup-imagemagick action ([d84fe2b](https://github.com/jksy/setup-imagemagick/commit/d84fe2b567e6f6612bd4c4e17a2a5fa7172fdf04))
* support snapshot release tags (X.Y.Z-N-YYYYMMDD) ([cedd422](https://github.com/jksy/setup-imagemagick/commit/cedd422030d5fc33f53f20bd33e673e7d12f2ce3))
* support snapshot release tags (X.Y.Z-N-YYYYMMDD) ([506609c](https://github.com/jksy/setup-imagemagick/commit/506609c2c08a6a56cefa9098cc1273f64ec376ec))


### Bug Fixes

* **ci:** set explicit ruby version for rmagick test workflow ([564d8b9](https://github.com/jksy/setup-imagemagick/commit/564d8b9d004acea091a3c35db6fcc3891aac1c2f))
* handle snapshot tags with collision suffix (X.Y.Z-N-YYYYMMDD-M) ([9c283a9](https://github.com/jksy/setup-imagemagick/commit/9c283a9fc30231bf1b0c73b35496c9c75a292e7b))
* install ghostscript before PDF conversion checks ([7b5c11a](https://github.com/jksy/setup-imagemagick/commit/7b5c11a61697e9365c005c0cf074f4ce3157f925))
* remove curl from AL2023 deps (curl-minimal already installed) ([82a3560](https://github.com/jksy/setup-imagemagick/commit/82a3560bcc00169e546dd8e286eb8ae9fd89343a))
* support non-variant asset names and add executable RMagick CI test ([8631d9a](https://github.com/jksy/setup-imagemagick/commit/8631d9ae7830ceb871645d26a636b5e097710fda))
* tighten token validation and sed escaping ([3491318](https://github.com/jksy/setup-imagemagick/commit/3491318528276a7427198e929152d24eb93b8903))
* use pkgconf-pkg-config for pkg-config command on AL2023 ([e445f6e](https://github.com/jksy/setup-imagemagick/commit/e445f6e506bd4189588259958654bbcafade211d))
