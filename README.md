# setup-imagemagick

Install prebuilt ImageMagick binaries from [jksy/imagemagick-build releases](https://github.com/jksy/imagemagick-build/releases).

## Usage

```yaml
- uses: jksy/setup-imagemagick@v2
  with:
    version: "7.1.2-34-20261028"
```

## Inputs

- `version` (required) — a release tag of jksy/imagemagick-build without the leading `v`: `7.1.2-34` (first build) or `7.1.2-34-20261028` (rebuild).
  Releases are immutable, so pin the dated tag to pick up rebuilds.
  See [jksy/imagemagick-build: Release naming](https://github.com/jksy/imagemagick-build?tab=readme-ov-file#release-naming--%E3%83%AA%E3%83%AA%E3%83%BC%E3%82%B9%E3%81%AE%E3%82%BF%E3%82%B0%E5%91%BD%E5%90%8D)
  and the [releases page](https://github.com/jksy/imagemagick-build/releases) for available versions.
- `install-prefix` (default: `${{ runner.temp }}/imagemagick`)
- `add-to-path` (default: `true`)
- `export-env` (default: `true`)
- `github-token` (default: `${{ github.token }}`) — used for GitHub API calls, to avoid the unauthenticated rate limit
- `verify-attestation` (default: `true`) — verify the build provenance attestation of the release asset before installing it. Requires the `gh` CLI (preinstalled on GitHub-hosted runners), but no extra permissions
- `fail-if-missing` — deprecated and ignored; a missing release asset always fails. Setting it prints a warning, and it will be removed in a future release

## Outputs

- `prefix`
- `bin-dir`
- `lib-dir`
- `pkg-config-path`
- `magick-path`
- `attestation-verified` — `true` when the attestation was verified, otherwise `false`

## Behavior

- Fetches `install.sh` of jksy/imagemagick-build at the release tag `v<version>` and runs it. The installer detects the OS / architecture, downloads the release asset, verifies its attestation (when `verify-attestation` is `true`) and extracts it
  - Supported targets are those of the installer: Ubuntu 22.04 / 24.04 / 26.04 and Amazon Linux 2023 / 2027, `x86_64` / `aarch64`
  - The installer runs with `sudo` when available, so that it can install missing runtime packages
- Copies the result into `install-prefix` and rewrites `lib/pkgconfig/*.pc` to point at it
- Logs dynamic-link (`ldd`) check for `libMagickCore*.so*`
- Installs `ghostscript` (when `gs` is missing) for PDF conversion support
- Exports:
  - `PATH=<prefix>/bin:$PATH` (when `add-to-path=true`)
  - `PKG_CONFIG_PATH=<prefix>/lib/pkgconfig:$PKG_CONFIG_PATH` (when `export-env=true`)
  - `LD_LIBRARY_PATH=<prefix>/lib:$LD_LIBRARY_PATH` (when `export-env=true`)

### Older versions

The installer is taken from the requested tag, so older tags run older installers.

- Tags whose installer cannot verify attestations install without verification. A warning is printed and `attestation-verified` is `false`
- Tags without an installer that supports `IMAGEMAGICK_VERSION` and `IMAGEMAGICK_INSTALL_BASE` (including tags with no `install.sh`, such as `7.1.2-18-20260405`) fail. Use `jksy/setup-imagemagick@v1` for them

## Migrating from v1

- Releases are installed by the installer of jksy/imagemagick-build instead of a separate implementation
- `verify-attestation` is on by default. In containers without `gh`, install `gh` or set `verify-attestation: false`
- `github-token` defaults to `${{ github.token }}`
- `fail-if-missing` is ignored

## Verification in CI

This repository includes `.github/workflows/test.yml`, which validates:

- the attestation of the latest release is verified
- `magick -version`
- `magick -list format | grep -E "JPEG|PNG|WEBP|AVIF"`
- image export to `JPG` / `WEBP` / `AVIF`
- `gs` availability and PDF (`input.pdf`) to PNG conversion
- `pkg-config --modversion MagickCore`
- RMagick installation and load:
  - `bundle init`
  - `gem "rmagick"` in `Gemfile`
  - `bundle install`
  - `ruby -e 'require "rmagick"; puts Magick::Magick_version'`
  - PDF (`input-rmagick.pdf`) to PNG conversion via RMagick

## Quick verification in workflow

```yaml
- run: magick -version
- run: magick -list format | grep -E "JPEG|PNG|WEBP|AVIF"
- run: pkg-config --modversion MagickCore
- run: |
    bundle init
    echo 'gem "rmagick"' >> Gemfile
    bundle install
    ruby -e 'require "rmagick"; puts Magick::Magick_version'
```
