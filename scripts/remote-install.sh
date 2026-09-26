#!/data/data/com.termux/files/usr/bin/bash
# FreeBuff Termux immutable-ref bootstrap installer
set -euo pipefail
umask 077

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

validate_identifier() {
    local value="$1" label="$2"
    if [[ ! "${value}" =~ ^[[:alnum:]][[:alnum:]._-]{0,63}$ ]] || [[ "${value}" == "." ]] || [[ "${value}" == ".." ]]; then
        log_error "Invalid ${label} identifier."
        return 1
    fi
}

validate_ref() {
    local ref="$1"
    [[ "${ref}" =~ ^[0-9a-f]{40}$ ]] \
        || [[ "${ref}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][[:alnum:]._-]+)?$ ]]
}

if [[ -z "${PREFIX:-}" ]] || [[ ! "${PREFIX}" =~ ^/data/data/com\.termux[^/]*/files/usr/?$ ]]; then
    log_error "This script must be run inside Termux."
    exit 1
fi

DISTRO="${1:-ubuntu}"
FREEBUFF_TERMUX_REF="${FREEBUFF_TERMUX_REF:-}"
FREEBUFF_TERMUX_EXPECTED_COMMIT="${FREEBUFF_TERMUX_EXPECTED_COMMIT:-}"
FREEBUFF_TERMUX_ARTIFACT_SHA256="${FREEBUFF_TERMUX_ARTIFACT_SHA256:-}"
REPO_URL="https://github.com/Chiriri722/Freebuff_In_Termux.git"
SOURCE_ROOT="${XDG_DATA_HOME:-${HOME}/.local/share}/freebuff-termux/source"
validate_identifier "${DISTRO}" "distro"
if [[ -z "${FREEBUFF_TERMUX_REF}" ]] || ! validate_ref "${FREEBUFF_TERMUX_REF}"; then
    log_error "FREEBUFF_TERMUX_REF must be a version tag or full 40-character commit SHA."
    exit 1
fi
if [[ "${FREEBUFF_TERMUX_REF}" =~ ^[0-9a-f]{40}$ ]]; then
    FREEBUFF_TERMUX_EXPECTED_COMMIT="${FREEBUFF_TERMUX_REF}"
elif [[ ! "${FREEBUFF_TERMUX_EXPECTED_COMMIT}" =~ ^[0-9a-f]{40}$ ]]; then
    log_error "A version tag also requires FREEBUFF_TERMUX_EXPECTED_COMMIT."
    exit 1
fi
if [[ ! "${FREEBUFF_TERMUX_REF}" =~ ^[0-9a-f]{40}$ ]] && [[ ! "${FREEBUFF_TERMUX_ARTIFACT_SHA256}" =~ ^[0-9a-f]{64}$ ]]; then
    log_error "A version tag also requires FREEBUFF_TERMUX_ARTIFACT_SHA256."
    exit 1
fi

log_info "Installing bootstrap dependencies without a global package upgrade..."
pkg update -y
pkg install -y git curl ca-certificates

STAGING_DIR="$(mktemp -d "${TMPDIR:-${PREFIX}/tmp}/freebuff-bootstrap.XXXXXX")"
cleanup() {
    local status=$?
    trap - EXIT
    if [[ -n "${CURRENT_TEMP:-}" ]]; then rm -f -- "${CURRENT_TEMP}"; fi
    rm -rf -- "${STAGING_DIR}"
    exit "${status}"
}
trap cleanup EXIT

if [[ "${FREEBUFF_TERMUX_REF}" =~ ^[0-9a-f]{40}$ ]]; then
    REPOSITORY="${STAGING_DIR}/repository"
    git init -q "${REPOSITORY}"
    git -C "${REPOSITORY}" remote add origin "${REPO_URL}"
    git -C "${REPOSITORY}" fetch --quiet --depth 1 origin "${FREEBUFF_TERMUX_REF}"
    SOURCE_COMMIT="$(git -C "${REPOSITORY}" rev-parse 'FETCH_HEAD^{commit}')"
    git -C "${REPOSITORY}" checkout --quiet --detach "${SOURCE_COMMIT}"
else
    ARTIFACT_NAME="freebuff-termux-${FREEBUFF_TERMUX_REF}.tar.gz"
    ARTIFACT_PATH="${STAGING_DIR}/${ARTIFACT_NAME}"
    ARTIFACT_URL="https://github.com/Chiriri722/Freebuff_In_Termux/releases/download/${FREEBUFF_TERMUX_REF}/${ARTIFACT_NAME}"
    curl --fail --silent --show-error --location "${ARTIFACT_URL}" -o "${ARTIFACT_PATH}"
    printf '%s  %s\n' "${FREEBUFF_TERMUX_ARTIFACT_SHA256}" "${ARTIFACT_PATH}" | sha256sum -c -
    tar -xzf "${ARTIFACT_PATH}" -C "${STAGING_DIR}"
    REPOSITORY="${STAGING_DIR}/freebuff-termux-${FREEBUFF_TERMUX_REF}"
    RELEASE_METADATA="${REPOSITORY}/RELEASE-METADATA"
    if [[ ! -f "${RELEASE_METADATA}" ]] || [[ -L "${RELEASE_METADATA}" ]]; then
        log_error "Release artifact metadata is missing or unsafe."
        exit 1
    fi
    metadata_value() {
        local key="$1"
        awk -v key="${key}" 'index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }' "${RELEASE_METADATA}"
    }
    if [[ "$(metadata_value schema)" != "1" ]] || [[ "$(metadata_value tag)" != "${FREEBUFF_TERMUX_REF}" ]]; then
        log_error "Release artifact metadata does not match the requested tag."
        exit 1
    fi
    SOURCE_COMMIT="$(metadata_value commit)"
fi
if [[ "${SOURCE_COMMIT}" != "${FREEBUFF_TERMUX_EXPECTED_COMMIT}" ]]; then
    log_error "Fetched commit does not match FREEBUFF_TERMUX_REF."
    exit 1
fi

INSTALL_DIR="${SOURCE_ROOT}/${SOURCE_COMMIT}"
mkdir -p "${SOURCE_ROOT}"
verify_existing_source() {
    local installed="$1" verified="$2" relative
    if [[ ! -d "${installed}" ]] || [[ -L "${installed}" ]]; then
        log_error "Existing source directory is unsafe."
        return 1
    fi
    for relative in \
        scripts/install.sh \
        scripts/remote-install.sh \
        scripts/freebuff-wrapper.sh \
        scripts/manage.sh \
        scripts/xdg-open-bridge.sh \
        scripts/lib/install-transaction.sh \
        skill/freebuff-hermes-integration/scripts/health_check.sh; do
        if [[ ! -f "${installed}/${relative}" ]] || [[ -L "${installed}/${relative}" ]] \
            || [[ "$(sha256sum "${installed}/${relative}" | awk '{print $1}')" != "$(sha256sum "${verified}/${relative}" | awk '{print $1}')" ]]; then
            log_error "Existing verified source was modified: ${relative}"
            return 1
        fi
    done
}

if [[ -e "${INSTALL_DIR}" ]] || [[ -L "${INSTALL_DIR}" ]]; then
    verify_existing_source "${INSTALL_DIR}" "${REPOSITORY}"
else
    mv -- "${REPOSITORY}" "${INSTALL_DIR}"
fi
CURRENT_LINK="${SOURCE_ROOT}/current"
if [[ -e "${CURRENT_LINK}" ]] && [[ ! -L "${CURRENT_LINK}" ]]; then
    log_error "Refusing to replace a non-symlink source/current path."
    exit 1
fi
CURRENT_TEMP="${SOURCE_ROOT}/.current.$$"

export FREEBUFF_TERMUX_SOURCE_REF="${FREEBUFF_TERMUX_REF}"
export FREEBUFF_TERMUX_SOURCE_COMMIT="${SOURCE_COMMIT}"
log_ok "Verified source checkout: ${FREEBUFF_TERMUX_REF} (${SOURCE_COMMIT})"
"${BASH}" "${INSTALL_DIR}/scripts/install.sh" "${DISTRO}"
ln -s -- "${INSTALL_DIR}" "${CURRENT_TEMP}"
mv -Tf -- "${CURRENT_TEMP}" "${CURRENT_LINK}"
