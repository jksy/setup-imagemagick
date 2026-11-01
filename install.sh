#!/usr/bin/env bash
# Runs the install.sh of jksy/imagemagick-build at the requested release tag,
# then moves the result to install-prefix and wires it into the job.
set -euo pipefail

REPO="jksy/imagemagick-build"
ORIGINAL_PREFIX="/opt/imagemagick"

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_true() {
  [[ "$(to_lower "$1")" == "true" ]]
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

run_privileged() {
  if [[ "$(id -u)" != "0" ]] && command_exists sudo; then
    sudo "$@"
  else
    "$@"
  fi
}

# apt blocks for a long time when a mirror is unresponsive, which can stall
# the whole job until timeout-minutes. Fail fast instead. Acquire::*::Timeout
# alone does not cover a mirror that accepts connections but stops responding,
# so apt-get invocations are additionally bounded with timeout(1).
APT_OPTS=(-o Acquire::http::Timeout=10 -o Acquire::https::Timeout=10 -o Acquire::Retries=2)
APT_HARD_TIMEOUT_SECONDS=300

install_ghostscript_if_missing() {
  if command_exists gs; then
    echo "::notice::Ghostscript already available"
    return
  fi

  if command_exists apt-get; then
    echo "::notice::Installing Ghostscript via apt-get"
    # A single unreachable repository (e.g. security.ubuntu.com, which has no
    # mirror fallback) must not abort the install. apt saves each index it did
    # fetch, so ghostscript can still be installed from the remaining sources.
    if ! run_privileged timeout "$APT_HARD_TIMEOUT_SECONDS" apt-get "${APT_OPTS[@]}" update; then
      echo "::warning::apt-get update failed or timed out; installing from the package lists that were fetched"
    fi
    run_privileged timeout "$APT_HARD_TIMEOUT_SECONDS" apt-get "${APT_OPTS[@]}" install -y ghostscript
  elif command_exists dnf; then
    echo "::notice::Installing Ghostscript via dnf"
    run_privileged dnf install -y ghostscript
  else
    echo "::error::Ghostscript is required for PDF conversion, but neither apt-get nor dnf is available" >&2
    exit 1
  fi

  if ! command_exists gs; then
    echo "::error::Ghostscript installation completed but gs command was not found" >&2
    exit 1
  fi
}

emit_outputs() {
  local prefix="$1"
  local magick_path="$2"
  local verified="$3"
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
    echo "attestation-verified=$verified"
  } >>"$output_file"
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

sed_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//&/\\&}"
  s="${s//#/\\#}"
  printf '%s' "$s"
}

# The installer leaves the .pc files pointing at the staging directory; older
# installers also leave the build prefix /opt/imagemagick outside prefix=.
# A placeholder keeps an install-prefix that contains /opt/imagemagick from
# being rewritten twice.
rewrite_pkgconfig_prefix() {
  local prefix="$1"
  local staged="$2"
  local pkg_dir="$prefix/lib/pkgconfig"
  local placeholder="@SETUP_IMAGEMAGICK_PREFIX@"

  if [[ ! -d "$pkg_dir" ]]; then
    return
  fi

  local staged_re original_re dest
  staged_re="$(sed_escape "$staged")"
  original_re="$(sed_escape "$ORIGINAL_PREFIX")"
  dest="$(sed_escape "$prefix")"

  while IFS= read -r -d '' pc_file; do
    sed -i \
      -e "s#$staged_re#$placeholder#g" \
      -e "s#$original_re#$placeholder#g" \
      -e "s#$placeholder#$dest#g" \
      "$pc_file"
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
VERIFY_ATTESTATION="${INPUT_VERIFY_ATTESTATION:-true}"

if [[ -n "${INPUT_FAIL_IF_MISSING:-}" ]]; then
  echo "::warning::fail-if-missing is deprecated and ignored; a missing release asset always fails. It will be removed in a future release."
fi

if [[ "${INPUT_GITHUB_TOKEN:-}" == *$'\n'* || "${INPUT_GITHUB_TOKEN:-}" == *$'\r'* ]]; then
  echo "::error::github-token contains invalid newline characters" >&2
  exit 1
fi

TAG="v${VERSION#v}"
# Snapshot tags have the form X.Y.Z-N-YYYYMMDD; the installed directory uses only X.Y.Z-N
if [[ "${TAG#v}" =~ ^([0-9]+\.[0-9]+\.[0-9]+-[0-9]+)(-[0-9]{8}(-[0-9]+)?)?$ ]]; then
  ASSET_VERSION="${BASH_REMATCH[1]}"
else
  echo "::error::Unsupported version format: $VERSION (expected X.Y.Z-N or X.Y.Z-N-YYYYMMDD)" >&2
  exit 1
fi

work_dir="$(mktemp -d -t setup-imagemagick-XXXXXX)"
cleanup() {
  # The installer may run as root, so the staged files can be root-owned.
  rm -rf "$work_dir" 2>/dev/null || run_privileged rm -rf "$work_dir"
}
trap cleanup EXIT

installer="$work_dir/install.sh"
# refs/tags/ keeps a branch with the same name from being picked instead.
installer_url="https://raw.githubusercontent.com/${REPO}/refs/tags/${TAG}/install.sh"
echo "::notice::Fetching installer from $installer_url"
http_code="$(curl -sS -L --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 2 \
  -o "$installer" -w '%{http_code}' "$installer_url" || true)"
if [[ "$http_code" == "404" ]]; then
  echo "::error::$REPO has no release tag $TAG, or the tag has no install.sh. Use a newer version, or jksy/setup-imagemagick@v1." >&2
  exit 1
elif [[ "$http_code" != "200" ]]; then
  echo "::error::Failed to fetch $installer_url (HTTP ${http_code:-none})" >&2
  exit 1
fi

# Installers from older tags ignore these variables and would silently install
# the latest release into /opt.
for required in IMAGEMAGICK_VERSION IMAGEMAGICK_INSTALL_BASE; do
  if ! grep -q "$required" "$installer"; then
    echo "::error::The installer of $TAG does not support $required. Use a newer version, or jksy/setup-imagemagick@v1." >&2
    exit 1
  fi
done

verify_env="0"
verified="false"
if is_true "$VERIFY_ATTESTATION"; then
  if grep -q "IMAGEMAGICK_VERIFY_ATTESTATION" "$installer"; then
    if ! command_exists gh; then
      echo "::error::verify-attestation requires the gh CLI. Install gh, or set verify-attestation: false." >&2
      exit 1
    fi
    verify_env="1"
    verified="true"
  else
    echo "::warning::The installer of $TAG cannot verify the build provenance attestation; installing without verification. Use a newer version to verify it."
  fi
fi

stage_base="$work_dir/stage"
mkdir -p "$stage_base"
installer_env=(
  "IMAGEMAGICK_VERSION=$TAG"
  "IMAGEMAGICK_INSTALL_BASE=$stage_base"
  "IMAGEMAGICK_VERIFY_ATTESTATION=$verify_env"
  "GITHUB_TOKEN=${INPUT_GITHUB_TOKEN:-}"
)
# Root lets the installer add missing runtime packages (libgomp, jq, ...).
run_privileged env "${installer_env[@]}" bash "$installer"

staged="$stage_base/imagemagick/$ASSET_VERSION"
if [[ ! -x "$staged/bin/magick" ]]; then
  echo "::error::The installer did not install ImageMagick $ASSET_VERSION (expected $staged/bin/magick)" >&2
  ls -la "$stage_base/imagemagick" >&2 || true
  exit 1
fi

mkdir -p "$INSTALL_PREFIX"
tar -C "$staged" -cf - . | tar --no-same-owner --no-same-permissions -C "$INSTALL_PREFIX" -xf -

MAGICK_PATH="$INSTALL_PREFIX/bin/magick"
if [[ ! -x "$MAGICK_PATH" ]]; then
  echo "::error::magick binary not found after installation: $MAGICK_PATH" >&2
  exit 1
fi

rewrite_pkgconfig_prefix "$INSTALL_PREFIX" "$staged"
log_rpath_related_info "$INSTALL_PREFIX/lib"
install_ghostscript_if_missing
append_env_if_requested "$INSTALL_PREFIX" "$ADD_TO_PATH" "$EXPORT_ENV"
emit_outputs "$INSTALL_PREFIX" "$MAGICK_PATH" "$verified"

LD_LIBRARY_PATH="$INSTALL_PREFIX/lib:${LD_LIBRARY_PATH:-}" "$MAGICK_PATH" -version

echo "::group::Bundled library versions"
VERSIONS_FILE="$INSTALL_PREFIX/VERSIONS"
if [[ -f "$VERSIONS_FILE" ]]; then
  while IFS='=' read -r lib_name lib_ver; do
    printf '  %-20s %s\n' "$lib_name" "$lib_ver"
  done < "$VERSIONS_FILE"
else
  echo "::warning::VERSIONS file not found (older release)"
fi
echo "::endgroup::"
