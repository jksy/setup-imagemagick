#!/usr/bin/env bash
set -euo pipefail

ORIGINAL_PREFIX="/opt/imagemagick"

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_true() {
  [[ "$(to_lower "$1")" == "true" ]]
}

require_linux_x86_64() {
  local runner_os="${RUNNER_OS:-Linux}"
  if [[ "$runner_os" != "Linux" ]]; then
    echo "::error::Unsupported RUNNER_OS: $runner_os (Linux only)"
    exit 1
  fi

  local machine
  machine="$(uname -m)"
  case "$machine" in
    x86_64|amd64)
      echo "x86_64"
      ;;
    *)
      echo "::error::Unsupported architecture: $machine (x86_64 only)" >&2
      exit 1
      ;;
  esac
}

detect_ubuntu_label() {
  if [[ -n "${ImageOS:-}" ]]; then
    case "$ImageOS" in
      ubuntu22|ubuntu22.04) echo "ubuntu22.04"; return ;;
      ubuntu24|ubuntu24.04) echo "ubuntu24.04"; return ;;
    esac
  fi

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    case "${VERSION_ID:-}" in
      22.04) echo "ubuntu22.04"; return ;;
      24.04) echo "ubuntu24.04"; return ;;
    esac
  fi

  echo "::error::Unsupported Ubuntu version. Supported: ubuntu-22.04 / ubuntu-24.04" >&2
  exit 1
}

emit_outputs() {
  local prefix="$1"
  local magick_path="$2"
  local output_file="${GITHUB_OUTPUT:-}"

  if [[ -z "$output_file" ]]; then
    return
  fi

  {
    echo "prefix=$prefix"
    echo "bin-dir=$prefix/bin"
    echo "lib-dir=$prefix/lib"
    echo "pkg-config-path=$prefix/lib/pkgconfig"
    echo "magick-path=$magick_path"
  } >>"$output_file"
}

validate_archive_paths() {
  local archive="$1"
  local bad_entries
  bad_entries="$(tar -tzf "$archive" | grep -E '^/|(^|/)\.\.(/|$)' || true)"
  if [[ -n "$bad_entries" ]]; then
    echo "::error::Archive contains unsafe paths"
    printf '%s\n' "$bad_entries"
    exit 1
  fi
}

append_env_if_requested() {
  local prefix="$1"
  local add_to_path="$2"
  local export_env="$3"

  if is_true "$add_to_path" && [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "$prefix/bin" >>"$GITHUB_PATH"
  fi

  if is_true "$export_env" && [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "PKG_CONFIG_PATH=$prefix/lib/pkgconfig:${PKG_CONFIG_PATH:-}" >>"$GITHUB_ENV"
    echo "LD_LIBRARY_PATH=$prefix/lib:${LD_LIBRARY_PATH:-}" >>"$GITHUB_ENV"
  fi
}

download_http_code() {
  local url="$1"
  local archive="$2"
  local code

  if [[ -n "${INPUT_GITHUB_TOKEN:-}" ]]; then
    if [[ "${INPUT_GITHUB_TOKEN:-}" == *$'\n'* || "${INPUT_GITHUB_TOKEN:-}" == *$'\r'* ]]; then
      echo "::error::github-token contains invalid newline characters" >&2
      exit 1
    fi
    code="$(curl -sS -L --retry 3 --retry-delay 2 -H "Authorization: Bearer ${INPUT_GITHUB_TOKEN:-}" -o "$archive" -w "%{http_code}" "$url" || true)"
  else
    code="$(curl -sS -L --retry 3 --retry-delay 2 -o "$archive" -w "%{http_code}" "$url" || true)"
  fi

  printf '%s' "$code"
}

rewrite_pkgconfig_prefix() {
  local prefix="$1"
  local pkg_dir="$prefix/lib/pkgconfig"

  if [[ ! -d "$pkg_dir" ]]; then
    return
  fi

  local escaped
  escaped="$prefix"
  escaped="${escaped//\\/\\\\}"
  escaped="${escaped//&/\\&}"
  escaped="${escaped//#/\\#}"

  while IFS= read -r -d '' pc_file; do
    sed -i "s#$ORIGINAL_PREFIX#$escaped#g" "$pc_file"
  done < <(find "$pkg_dir" -type f -name '*.pc' -print0)
}

log_rpath_related_info() {
  local lib_dir="$1"
  local candidate

  if [[ ! -d "$lib_dir" ]]; then
    echo "::notice::RPATH check skipped: $lib_dir does not exist"
    return
  fi

  candidate="$(find "$lib_dir" -maxdepth 1 -type f -name 'libMagickCore*.so*' | head -n 1 || true)"
  if [[ -z "$candidate" ]]; then
    echo "::notice::RPATH check skipped: libMagickCore*.so not found"
    return
  fi

  echo "::group::ldd check for $candidate"
  local ldd_output
  ldd_output="$(ldd "$candidate" || true)"
  printf '%s\n' "$ldd_output"
  echo "::endgroup::"

  if grep -q "$ORIGINAL_PREFIX" <<<"$ldd_output"; then
    echo "::warning::Detected $ORIGINAL_PREFIX in ldd output. patchelf handling is not applied in this version."
  else
    echo "::notice::No /opt/imagemagick path detected in ldd output"
  fi
}

VERSION="${INPUT_VERSION:?INPUT_VERSION is required}"
DEFAULT_PREFIX="${RUNNER_TEMP:-/tmp}/imagemagick"
INSTALL_PREFIX="${INPUT_INSTALL_PREFIX:-$DEFAULT_PREFIX}"
ADD_TO_PATH="${INPUT_ADD_TO_PATH:-true}"
EXPORT_ENV="${INPUT_EXPORT_ENV:-true}"
FAIL_IF_MISSING="${INPUT_FAIL_IF_MISSING:-true}"

ARCH_LABEL="$(require_linux_x86_64)"
UBUNTU_LABEL="$(detect_ubuntu_label)"
ASSET_NAME="imagemagick-${VERSION}-${UBUNTU_LABEL}-${ARCH_LABEL}.tar.gz"
BASE_URL="${IMAGEMAGICK_RELEASE_BASE_URL:-https://github.com/jksy/imagemagick-build/releases/download}"

if [[ "$VERSION" == v* ]]; then
  TAG_CANDIDATES=("$VERSION" "${VERSION#v}")
else
  TAG_CANDIDATES=("v$VERSION" "$VERSION")
fi

archive_path="$(mktemp -t imagemagick-asset-XXXXXX.tar.gz)"
extract_dir=""
cleanup() {
  rm -f "$archive_path"
  if [[ -n "$extract_dir" ]]; then
    rm -rf "$extract_dir"
  fi
}
trap cleanup EXIT

selected_url=""
selected_asset_name=""
asset_found="false"

for tag in "${TAG_CANDIDATES[@]}"; do
  url="$BASE_URL/$tag/$ASSET_NAME"
  echo "::notice::Trying $url"
  http_code="$(download_http_code "$url" "$archive_path")"

  if [[ "$http_code" == "200" ]]; then
    selected_url="$url"
    selected_asset_name="$ASSET_NAME"
    asset_found="true"
    break
  fi

  if [[ "$http_code" != "404" ]]; then
    echo "::error::Download failed for $url (HTTP $http_code)"
    exit 1
  fi
done

if [[ "$asset_found" != "true" ]]; then
  if is_true "$FAIL_IF_MISSING"; then
    echo "::error::Release asset not found: $ASSET_NAME"
    exit 1
  fi

  echo "::warning::Release asset not found, skipping installation"
  emit_outputs "$INSTALL_PREFIX" ""
  exit 0
fi

echo "::notice::Downloading asset from $selected_url"
echo "::notice::Selected asset: $selected_asset_name"

validate_archive_paths "$archive_path"
extract_dir="$(mktemp -d -t imagemagick-extract-XXXXXX)"
tar --no-same-owner --no-same-permissions -xzf "$archive_path" -C "$extract_dir"

source_root=""
if [[ -x "$extract_dir/bin/magick" ]]; then
  source_root="$extract_dir"
else
  magick_in_archive="$(find "$extract_dir" -type f -path '*/bin/magick' | head -n 1 || true)"
  if [[ -n "$magick_in_archive" ]]; then
    source_root="$(dirname "$(dirname "$magick_in_archive")")"
  fi
fi

if [[ -z "$source_root" ]]; then
  echo "::error::magick binary not found in archive"
  exit 1
fi

mkdir -p "$INSTALL_PREFIX"
tar --no-same-owner --no-same-permissions -C "$source_root" -cf - . | tar --no-same-owner --no-same-permissions -C "$INSTALL_PREFIX" -xf -

MAGICK_PATH="$INSTALL_PREFIX/bin/magick"
if [[ ! -x "$MAGICK_PATH" ]]; then
  echo "::error::magick binary not found after extraction: $MAGICK_PATH"
  exit 1
fi

rewrite_pkgconfig_prefix "$INSTALL_PREFIX"
log_rpath_related_info "$INSTALL_PREFIX/lib"
append_env_if_requested "$INSTALL_PREFIX" "$ADD_TO_PATH" "$EXPORT_ENV"
emit_outputs "$INSTALL_PREFIX" "$MAGICK_PATH"

LD_LIBRARY_PATH="$INSTALL_PREFIX/lib:${LD_LIBRARY_PATH:-}" "$MAGICK_PATH" -version
