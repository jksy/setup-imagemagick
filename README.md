# setup-imagemagick

Install prebuilt ImageMagick binaries from [jksy/imagemagick-build releases](https://github.com/jksy/imagemagick-build/releases).

## Usage

```yaml
- uses: jksy/setup-imagemagick@v1
  with:
    version: "7.1.2-3"
    install-prefix: "${{ runner.temp }}/imagemagick"
    add-to-path: true
    export-env: true
    fail-if-missing: true
```

## Inputs

- `version` (required)
- `install-prefix` (default: `${{ runner.temp }}/imagemagick`)
- `add-to-path` (default: `true`)
- `export-env` (default: `true`)
- `github-token` (optional)
- `fail-if-missing` (default: `true`)

## Outputs

- `prefix`
- `bin-dir`
- `lib-dir`
- `pkg-config-path`
- `magick-path`

## Behavior

- Resolves runner OS/arch (`ubuntu-22.04` / `ubuntu-24.04`, `x86_64`)
- Downloads release asset:
  `imagemagick-${version}-ubuntu24.04-x86_64.tar.gz`
- Extracts into `install-prefix`
- Rewrites `lib/pkgconfig/*.pc` from `/opt/imagemagick` to your `install-prefix`
- Logs dynamic-link (`ldd`) check for `libMagickCore*.so*`
- Installs `ghostscript` (when `gs` is missing) for PDF conversion support
- Exports:
  - `PATH=<prefix>/bin:$PATH` (when `add-to-path=true`)
  - `PKG_CONFIG_PATH=<prefix>/lib/pkgconfig:$PKG_CONFIG_PATH` (when `export-env=true`)
  - `LD_LIBRARY_PATH=<prefix>/lib:$LD_LIBRARY_PATH` (when `export-env=true`)

## Verification in CI

This repository includes `.github/workflows/test.yml`, which validates:

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
