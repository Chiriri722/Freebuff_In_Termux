#!/data/data/com.termux/files/usr/bin/bash
# FreeBuff Termux canonical installer
set -euo pipefail
umask 077

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

validate_identifier() {
    local value="$1" label="$2"
    if [[ ! "${value}" =~ ^[[:alnum:]][[:alnum:]._-]{0,63}$ ]] || [[ "${value}" == "." ]] || [[ "${value}" == ".." ]]; then
        log_error "Invalid ${label} identifier."
        return 1
    fi
}

if [[ -z "${PREFIX:-}" ]] || [[ ! "${PREFIX}" =~ ^/data/data/com\.termux[^/]*/files/usr/?$ ]]; then
    log_error "This script must be run inside Termux."
    exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
TRANSACTION_LIBRARY="${REPO_ROOT}/scripts/lib/install-transaction.sh"
if [[ ! -f "${TRANSACTION_LIBRARY}" ]] || [[ -L "${TRANSACTION_LIBRARY}" ]]; then
    log_error "The installer transaction library is missing or unsafe."
    exit 1
fi
# shellcheck source=lib/install-transaction.sh
source "${TRANSACTION_LIBRARY}"
DISTRO="${1:-ubuntu}"
validate_identifier "${DISTRO}" "distro"

DEFAULT_NODE_VERSION='v22.17.1'
# Source: https://nodejs.org/dist/v22.17.1/SHASUMS256.txt
DEFAULT_NODE_ARM64_SHA256='f53510706998cf044f634190416f0588e7e1937aecea938768952e0f0ac1f41b'
DEFAULT_NODE_X64_SHA256='cfb6ac0cf339825fe36efd1f18a79016b02aca19fbfa6c9547c57e27dc09f6ea'
NODE_VERSION="${FREEBUFF_NODE_VERSION:-${DEFAULT_NODE_VERSION}}"
NODE_TARBALL_SHA256="${FREEBUFF_NODE_TARBALL_SHA256:-}"
DEFAULT_FREEBUFF_VERSION='0.0.152'
DEFAULT_FREEBUFF_TARBALL_SHA512='a63c9383e94a2501cda74df90a147080c6bd60942132afdec44ebdb465b362e6847cf9786a26aec8b00b7e8b11f571c346ecad7fbf5fd98b269edf35e8393e25'
FREEBUFF_VERSION="${FREEBUFF_VERSION:-${DEFAULT_FREEBUFF_VERSION}}"
validate_identifier "${NODE_VERSION}" "Node version"
validate_identifier "${FREEBUFF_VERSION}" "FreeBuff version"
if [[ "${FREEBUFF_VERSION}" == "${DEFAULT_FREEBUFF_VERSION}" ]]; then
    FREEBUFF_TARBALL_SHA512="${FREEBUFF_TARBALL_SHA512:-${DEFAULT_FREEBUFF_TARBALL_SHA512}}"
    if [[ "${FREEBUFF_TARBALL_SHA512}" != "${DEFAULT_FREEBUFF_TARBALL_SHA512}" ]]; then
        log_error "The pinned FreeBuff ${DEFAULT_FREEBUFF_VERSION} checksum cannot be overridden."
        exit 1
    fi
else
    FREEBUFF_TARBALL_SHA512="${FREEBUFF_TARBALL_SHA512:-}"
fi
if [[ ! "${FREEBUFF_TARBALL_SHA512}" =~ ^[0-9a-f]{128}$ ]]; then
    log_error "A custom FreeBuff version requires FREEBUFF_TARBALL_SHA512 (128 lowercase hex characters)."
    exit 1
fi

UBUNTU_IMAGE='ubuntu@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517'
DEBIAN_IMAGE='debian@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241'
PROOT_IMAGE="${FREEBUFF_PROOT_IMAGE:-}"
if [[ -z "${PROOT_IMAGE}" ]]; then
    case "${DISTRO}" in
        ubuntu) PROOT_IMAGE="${UBUNTU_IMAGE}" ;;
        debian) PROOT_IMAGE="${DEBIAN_IMAGE}" ;;
        *)
            log_error "Custom distro '${DISTRO}' requires FREEBUFF_PROOT_IMAGE=image@sha256:<digest>."
            exit 1
            ;;
    esac
fi
if [[ ${#PROOT_IMAGE} -gt 512 ]] || [[ ! "${PROOT_IMAGE}" =~ ^[a-z0-9][a-z0-9._:/-]*@sha256:[0-9a-f]{64}$ ]]; then
    log_error "FREEBUFF_PROOT_IMAGE must be an OCI image pinned by sha256 digest."
    exit 1
fi

WRAPPER_DIR="${HOME}/.local/bin"
WRAPPER_PATH="${WRAPPER_DIR}/freebuff"
MANAGER_PATH="${WRAPPER_DIR}/freebuff-termux"
CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/freebuff-termux"
DISTRO_FILE="${CONFIG_DIR}/distro"
STATE_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/freebuff-termux"
MANIFEST_PATH="${STATE_DIR}/install-manifest"
DISTRO_ROOTFS="${PREFIX}/var/lib/proot-distro/containers/${DISTRO}/rootfs"
BRIDGE_PATH="${DISTRO_ROOTFS}/usr/local/bin/xdg-open"
NODE_ROOT="/opt/freebuff-termux/node-${NODE_VERSION}"
FREEBUFF_ROOT="/opt/freebuff-termux/freebuff-${FREEBUFF_VERSION}"
NODE_ROOTFS="${DISTRO_ROOTFS}${NODE_ROOT}"
FREEBUFF_ROOTFS="${DISTRO_ROOTFS}${FREEBUFF_ROOT}"
NODE_CURRENT_ROOTFS="${DISTRO_ROOTFS}/opt/freebuff-termux/current-node"
FREEBUFF_CURRENT_ROOTFS="${DISTRO_ROOTFS}/opt/freebuff-termux/current-freebuff"
INSTALL_TRANSACTION_DIR="${STATE_DIR}/install-transaction"
TRANSACTION_TARGETS=(
    "${NODE_CURRENT_ROOTFS}"
    "${FREEBUFF_CURRENT_ROOTFS}"
    "${WRAPPER_PATH}"
    "${MANAGER_PATH}"
    "${BRIDGE_PATH}"
    "${DISTRO_FILE}"
    "${MANIFEST_PATH}"
)
PROOT_LOGIN=(proot-distro login --user root --isolated "${DISTRO}")
FREEBUFF_ALLOW_EXISTING_DISTRO="${FREEBUFF_ALLOW_EXISTING_DISTRO:-0}"
if [[ "${FREEBUFF_ALLOW_EXISTING_DISTRO}" != "0" ]] && [[ "${FREEBUFF_ALLOW_EXISTING_DISTRO}" != "1" ]]; then
    log_error "FREEBUFF_ALLOW_EXISTING_DISTRO must be 0 or 1."
    exit 1
fi

existing_manifest_value() {
    local key="$1"
    awk -v key="${key}" 'index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }' "${MANIFEST_PATH}"
}

if [[ -e "${INSTALL_TRANSACTION_DIR}" ]] || [[ -L "${INSTALL_TRANSACTION_DIR}" ]]; then
    log_warn "Recovering an interrupted managed-file transaction."
    if ! install_transaction_recover \
        "${INSTALL_TRANSACTION_DIR}" "${DISTRO}" "${TRANSACTION_TARGETS[@]}"; then
        log_error "Interrupted transaction state is invalid; no install target was changed."
        exit 1
    fi
fi

EXISTING_MANIFEST=0
if [[ -L "${MANIFEST_PATH}" ]]; then
    log_error "Refusing an unsafe install manifest symlink."
    exit 1
elif [[ -f "${MANIFEST_PATH}" ]]; then
    EXISTING_MANIFEST=1
    if [[ "$(existing_manifest_value schema)" != "2" ]] \
        || [[ "$(existing_manifest_value distro)" != "${DISTRO}" ]] \
        || [[ "$(existing_manifest_value proot_image)" != "${PROOT_IMAGE}" ]]; then
        log_error "Existing install manifest does not match the requested distro and pinned image."
        exit 1
    fi
fi

assert_managed_target() {
    local target="$1" path_key="$2" sha_key="$3" expected_sha
    if [[ ! -e "${target}" ]] && [[ ! -L "${target}" ]]; then
        return 0
    fi
    if [[ ${EXISTING_MANIFEST} -ne 1 ]] \
        || [[ "$(existing_manifest_value "${path_key}")" != "${target}" ]]; then
        log_error "Refusing to overwrite unmanaged target: ${target}"
        return 1
    fi
    expected_sha="$(existing_manifest_value "${sha_key}")"
    if [[ ! "${expected_sha}" =~ ^[0-9a-f]{64}$ ]] \
        || [[ ! -f "${target}" ]] || [[ -L "${target}" ]] \
        || [[ "$(sha256sum "${target}" | awk '{print $1}')" != "${expected_sha}" ]]; then
        log_error "Refusing to overwrite unmanaged or modified target: ${target}"
        return 1
    fi
}

assert_runtime_link() {
    local target="$1" manifest_target_key="$2" requested_target="$3" allowed_target
    if [[ ! -e "${target}" ]] && [[ ! -L "${target}" ]]; then
        return 0
    fi
    if [[ ! -L "${target}" ]]; then
        log_error "Refusing to overwrite unmanaged runtime target: ${target}"
        return 1
    fi
    allowed_target="${requested_target}"
    if [[ ${EXISTING_MANIFEST} -eq 1 ]]; then
        allowed_target="$(existing_manifest_value "${manifest_target_key}")"
    fi
    if [[ -z "${allowed_target}" ]] || [[ "$(readlink "${target}")" != "${allowed_target}" ]]; then
        log_error "Refusing to overwrite unmanaged runtime link: ${target}"
        return 1
    fi
}

runtime_marker_matches() {
    local root="$1" kind="$2" version="$3" digest_key="$4" digest="$5"
    local marker="${root}/.freebuff-termux-runtime" expected actual
    if [[ ! -f "${marker}" ]] || [[ -L "${marker}" ]]; then
        return 1
    fi
    expected="$(printf 'schema=1\nkind=%s\nversion=%s\n%s=%s' \
        "${kind}" "${version}" "${digest_key}" "${digest}")"
    actual="$(cat -- "${marker}")"
    [[ "${actual}" == "${expected}" ]]
}

assert_runtime_root() {
    local target="$1" manifest_key="$2" logical_root="$3" kind="$4"
    local version="$5" digest_key="$6" digest="$7" label="$8"
    local marker="${target}/.freebuff-termux-runtime"
    if [[ ! -e "${target}" ]] && [[ ! -L "${target}" ]]; then
        return 0
    fi
    if [[ ! -d "${target}" ]] || [[ -L "${target}" ]]; then
        log_error "Refusing unowned or unverified ${label} runtime root: ${target}"
        return 1
    fi
    if runtime_marker_matches "${target}" "${kind}" "${version}" "${digest_key}" "${digest}"; then
        return 0
    fi
    if [[ ${EXISTING_MANIFEST} -eq 1 ]] \
        && [[ "$(existing_manifest_value "${manifest_key}")" == "${logical_root}" ]] \
        && [[ ! -e "${marker}" ]] && [[ ! -L "${marker}" ]]; then
        log_warn "Accepting legacy manifest-owned ${label} runtime without an integrity marker."
        return 0
    fi
    log_error "Refusing unowned or unverified ${label} runtime root: ${target}"
    return 1
}

case "$(dpkg --print-architecture)" in
    aarch64 | arm64)
        NODE_ARCH='arm64'
        DEFAULT_NODE_TARBALL_SHA256="${DEFAULT_NODE_ARM64_SHA256}"
        ;;
    x86_64 | amd64)
        NODE_ARCH='x64'
        DEFAULT_NODE_TARBALL_SHA256="${DEFAULT_NODE_X64_SHA256}"
        ;;
    *)
        log_error "Unsupported architecture for the pinned Node.js build."
        exit 1
        ;;
esac
if [[ "${NODE_VERSION}" == "${DEFAULT_NODE_VERSION}" ]]; then
    if [[ -n "${NODE_TARBALL_SHA256}" ]] \
        && [[ "${NODE_TARBALL_SHA256}" != "${DEFAULT_NODE_TARBALL_SHA256}" ]]; then
        log_error "The pinned Node ${DEFAULT_NODE_VERSION} checksum cannot be overridden."
        exit 1
    fi
    NODE_TARBALL_SHA256="${DEFAULT_NODE_TARBALL_SHA256}"
elif [[ ! "${NODE_TARBALL_SHA256}" =~ ^[0-9a-f]{64}$ ]]; then
    log_error "A custom Node version requires FREEBUFF_NODE_TARBALL_SHA256 (64 lowercase hex characters)."
    exit 1
fi

if [[ ${EXISTING_MANIFEST} -eq 1 ]] && ! command -v sha256sum >/dev/null 2>&1; then
    log_error "sha256sum is required to validate the existing installation."
    exit 1
fi
assert_managed_target "${WRAPPER_PATH}" wrapper_path wrapper_sha256
assert_managed_target "${MANAGER_PATH}" manager_path manager_sha256
assert_managed_target "${DISTRO_FILE}" config_path config_sha256
assert_managed_target "${BRIDGE_PATH}" bridge_path bridge_sha256
assert_runtime_link "${NODE_CURRENT_ROOTFS}" node_root "${NODE_ROOT}"
assert_runtime_link "${FREEBUFF_CURRENT_ROOTFS}" freebuff_root "${FREEBUFF_ROOT}"
assert_runtime_root "${NODE_ROOTFS}" node_root "${NODE_ROOT}" node \
    "${NODE_VERSION}" archive_sha256 "${NODE_TARBALL_SHA256}" Node
assert_runtime_root "${FREEBUFF_ROOTFS}" freebuff_root "${FREEBUFF_ROOT}" freebuff \
    "${FREEBUFF_VERSION}" archive_sha512 "${FREEBUFF_TARBALL_SHA512}" FreeBuff

if [[ -d "${DISTRO_ROOTFS}" ]] && [[ ${EXISTING_MANIFEST} -ne 1 ]]; then
    if [[ "${FREEBUFF_ALLOW_EXISTING_DISTRO}" != "1" ]]; then
        log_error "Existing distro is not owned by FreeBuff Termux; set FREEBUFF_ALLOW_EXISTING_DISTRO=1 to adopt it explicitly."
        exit 1
    fi
    log_warn "Adopting the existing '${DISTRO}' distro without changing unrelated files."
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-${PREFIX}/tmp}/freebuff-termux.XXXXXX")"
TRANSACTION_ACTIVE=0

atomic_install() {
    local source="$1" target="$2" mode="$3" temp
    mkdir -p -- "$(dirname -- "${target}")"
    temp="$(mktemp "${target}.tmp.XXXXXX")"
    install -m "${mode}" -- "${source}" "${temp}"
    mv -f -- "${temp}" "${target}"
}

install_test_failpoint() {
    local stage="$1" requested="${FREEBUFF_INSTALL_TEST_FAILPOINT:-}"
    case "${requested}" in
        "${stage}") return 97 ;;
        "${stage}:term") kill -s TERM "$$" ;;
        "${stage}:hard") kill -s KILL "$$" ;;
        '') return 0 ;;
        *) return 0 ;;
    esac
}

cleanup() {
    local status=$?
    trap - EXIT
    if [[ ${status} -ne 0 ]] && [[ ${TRANSACTION_ACTIVE} -eq 1 ]]; then
        log_warn "Installation failed; restoring the complete managed-file set."
        if install_transaction_recover \
            "${INSTALL_TRANSACTION_DIR}" "${DISTRO}" "${TRANSACTION_TARGETS[@]}"; then
            TRANSACTION_ACTIVE=0
        else
            log_error "Automatic transaction recovery failed; the next installer run will retry it."
        fi
    fi
    if [[ -n "${NODE_STAGE:-}" ]]; then
        rm -rf -- "${NODE_STAGE}"
    fi
    if [[ -n "${DISTRO_ROOTFS:-}" ]] && [[ -n "${FREEBUFF_STAGE:-}" ]]; then
        rm -rf -- "${DISTRO_ROOTFS}${FREEBUFF_STAGE}"
    fi
    if [[ -n "${FREEBUFF_TARBALL_ROOTFS:-}" ]]; then
        rm -f -- "${FREEBUFF_TARBALL_ROOTFS}"
    fi
    rm -rf -- "${WORK_DIR}"
    exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

log_info "Repairing interrupted dpkg configuration, if any..."
if ! dpkg --configure -a; then
    log_error "dpkg repair failed; no package upgrade was attempted."
    exit 1
fi

log_info "Installing required Termux packages without a global upgrade..."
pkg update -y
pkg install -y proot-distro git curl ca-certificates termux-api util-linux
command -v proot-distro >/dev/null
command -v sha256sum >/dev/null
command -v sha512sum >/dev/null
command -v setsid >/dev/null

if [[ ! -d "${DISTRO_ROOTFS}" ]]; then
    log_info "Installing digest-pinned ${PROOT_IMAGE} as ${DISTRO}..."
    proot-distro install --name "${DISTRO}" "${PROOT_IMAGE}"
fi
if [[ ! -d "${DISTRO_ROOTFS}" ]]; then
    log_error "Distro rootfs was not created: ${DISTRO_ROOTFS}"
    exit 1
fi

NODE_ARCHIVE="node-${NODE_VERSION}-linux-${NODE_ARCH}.tar.gz"
NODE_BASE_URL="https://nodejs.org/dist/${NODE_VERSION}"
NODE_ARCHIVE_PATH="${WORK_DIR}/${NODE_ARCHIVE}"

if [[ ! -x "${NODE_ROOTFS}/bin/node" ]]; then
    log_info "Downloading pinned Node.js ${NODE_VERSION} (${NODE_ARCH})..."
    curl --fail --silent --show-error --location \
        "${NODE_BASE_URL}/${NODE_ARCHIVE}" -o "${NODE_ARCHIVE_PATH}"
    printf '%s  %s\n' "${NODE_TARBALL_SHA256}" "${NODE_ARCHIVE_PATH}" | sha256sum -c -

    NODE_STAGE="${NODE_ROOTFS}.tmp.$$"
    rm -rf -- "${NODE_STAGE}"
    mkdir -p -- "${NODE_STAGE}"
    tar -xzf "${NODE_ARCHIVE_PATH}" -C "${NODE_STAGE}" --strip-components=1
    cat >"${NODE_STAGE}/.freebuff-termux-runtime" <<MARKER
schema=1
kind=node
version=${NODE_VERSION}
archive_sha256=${NODE_TARBALL_SHA256}
MARKER
    chmod 0600 "${NODE_STAGE}/.freebuff-termux-runtime"
    rm -rf -- "${NODE_ROOTFS}"
    mv -- "${NODE_STAGE}" "${NODE_ROOTFS}"
fi

FREEBUFF_STAGE="${FREEBUFF_ROOT}.tmp.$$"
if ! "${PROOT_LOGIN[@]}" -- /bin/bash --norc --noprofile -c \
    'test -x "$1/bin/freebuff"' -- "${FREEBUFF_ROOT}"; then
    log_info "Installing pinned FreeBuff ${FREEBUFF_VERSION}..."
    FREEBUFF_TARBALL_NAME="freebuff-${FREEBUFF_VERSION}.tgz"
    FREEBUFF_TARBALL_PATH="${WORK_DIR}/${FREEBUFF_TARBALL_NAME}"
    FREEBUFF_TARBALL_PROOT="/tmp/freebuff-termux-${FREEBUFF_VERSION}.$$.tgz"
    FREEBUFF_TARBALL_ROOTFS="${DISTRO_ROOTFS}${FREEBUFF_TARBALL_PROOT}"
    curl --fail --silent --show-error --location \
        "https://registry.npmjs.org/freebuff/-/${FREEBUFF_TARBALL_NAME}" -o "${FREEBUFF_TARBALL_PATH}"
    printf '%s  %s\n' "${FREEBUFF_TARBALL_SHA512}" "${FREEBUFF_TARBALL_PATH}" | sha512sum -c -
    install -m 0600 -- "${FREEBUFF_TARBALL_PATH}" "${FREEBUFF_TARBALL_ROOTFS}"
    "${PROOT_LOGIN[@]}" -- /bin/bash --norc --noprofile -c \
        'set -e; node_root="$1"; stage="$2"; target="$3"; tarball="$4"; version="$5"; digest="$6"; rm -rf -- "$stage" "$target"; export PATH="$node_root/bin:/usr/bin:/bin"; "$node_root/bin/npm" install -g --prefix "$stage" "$tarball"; test -x "$stage/bin/freebuff"; printf "schema=1\nkind=freebuff\nversion=%s\narchive_sha512=%s\n" "$version" "$digest" >"$stage/.freebuff-termux-runtime"; chmod 600 "$stage/.freebuff-termux-runtime"; mv -- "$stage" "$target"' \
        -- "${NODE_ROOT}" "${FREEBUFF_STAGE}" "${FREEBUFF_ROOT}" "${FREEBUFF_TARBALL_PROOT}" \
        "${FREEBUFF_VERSION}" "${FREEBUFF_TARBALL_SHA512}"
    rm -f -- "${FREEBUFF_TARBALL_ROOTFS}"
    FREEBUFF_TARBALL_ROOTFS=""
fi

install_transaction_begin \
    "${INSTALL_TRANSACTION_DIR}" "${DISTRO}" "${TRANSACTION_TARGETS[@]}"
TRANSACTION_ACTIVE=1
install_test_failpoint after_backup

"${PROOT_LOGIN[@]}" -- /bin/bash --norc --noprofile -c \
    'set -e; node_root="$1"; freebuff_root="$2"; mkdir -p /opt/freebuff-termux; ln -sfn "$node_root" /opt/freebuff-termux/current-node; ln -sfn "$freebuff_root" /opt/freebuff-termux/current-freebuff' \
    -- "${NODE_ROOT}" "${FREEBUFF_ROOT}"

remove_legacy_runtime_links() {
    "${PROOT_LOGIN[@]}" -- /bin/bash --norc --noprofile -c \
        'set -e; remove_owned_link() { target="$1"; expected="$2"; if test -L "$target" && test "$(readlink "$target")" = "$expected"; then rm -f -- "$target"; fi; }; remove_owned_link /usr/local/bin/node /opt/freebuff-termux/current-node/bin/node; remove_owned_link /usr/local/bin/npm /opt/freebuff-termux/current-node/bin/npm; remove_owned_link /usr/local/bin/freebuff /opt/freebuff-termux/current-freebuff/bin/freebuff'
}

log_info "Installing canonical wrapper and URL bridge atomically..."
atomic_install "${REPO_ROOT}/scripts/freebuff-wrapper.sh" "${WRAPPER_PATH}" 0755
install_test_failpoint after_first_asset_commit
atomic_install "${REPO_ROOT}/scripts/manage.sh" "${MANAGER_PATH}" 0755
atomic_install "${REPO_ROOT}/scripts/xdg-open-bridge.sh" "${BRIDGE_PATH}" 0755
printf '%s\n' "${DISTRO}" >"${WORK_DIR}/distro"
atomic_install "${WORK_DIR}/distro" "${DISTRO_FILE}" 0600

WRAPPER_SHA="$(sha256sum "${REPO_ROOT}/scripts/freebuff-wrapper.sh" | awk '{print $1}')"
MANAGER_SHA="$(sha256sum "${REPO_ROOT}/scripts/manage.sh" | awk '{print $1}')"
BRIDGE_SHA="$(sha256sum "${REPO_ROOT}/scripts/xdg-open-bridge.sh" | awk '{print $1}')"
CONFIG_SHA="$(sha256sum "${WORK_DIR}/distro" | awk '{print $1}')"
INSTALLER_SHA="$(sha256sum "${REPO_ROOT}/scripts/install.sh" | awk '{print $1}')"
BOOTSTRAP_SHA="$(sha256sum "${REPO_ROOT}/scripts/remote-install.sh" | awk '{print $1}')"
SOURCE_COMMIT="${FREEBUFF_TERMUX_SOURCE_COMMIT:-}"
if [[ -z "${SOURCE_COMMIT}" ]] && command -v git >/dev/null 2>&1; then
    SOURCE_COMMIT="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || true)"
fi
if [[ ! "${SOURCE_COMMIT}" =~ ^[0-9a-f]{40}$ ]]; then SOURCE_COMMIT='unknown'; fi
cat >"${WORK_DIR}/install-manifest" <<MANIFEST
schema=2
distro=${DISTRO}
proot_image=${PROOT_IMAGE}
node_version=${NODE_VERSION}
node_tarball_sha256=${NODE_TARBALL_SHA256}
freebuff_version=${FREEBUFF_VERSION}
freebuff_tarball_sha512=${FREEBUFF_TARBALL_SHA512}
source_ref=${FREEBUFF_TERMUX_SOURCE_REF:-local}
source_commit=${SOURCE_COMMIT}
source_path=${REPO_ROOT}
installer_sha256=${INSTALLER_SHA}
bootstrap_sha256=${BOOTSTRAP_SHA}
wrapper_path=${WRAPPER_PATH}
wrapper_sha256=${WRAPPER_SHA}
manager_path=${MANAGER_PATH}
manager_sha256=${MANAGER_SHA}
bridge_path=${BRIDGE_PATH}
bridge_sha256=${BRIDGE_SHA}
config_path=${DISTRO_FILE}
config_sha256=${CONFIG_SHA}
node_root=${NODE_ROOT}
freebuff_root=${FREEBUFF_ROOT}
MANIFEST
install_test_failpoint before_manifest_commit
atomic_install "${WORK_DIR}/install-manifest" "${MANIFEST_PATH}" 0600
install_test_failpoint after_manifest_commit
install_test_failpoint before_backup_cleanup
install_transaction_commit "${INSTALL_TRANSACTION_DIR}"
TRANSACTION_ACTIVE=0

remove_legacy_runtime_links
log_ok "FreeBuff Termux installation complete."
echo -e "Distro: ${BLUE}${DISTRO}${NC}"
echo -e "Wrapper: ${BLUE}${WRAPPER_PATH}${NC}"
echo -e "Manager: ${BLUE}${MANAGER_PATH}${NC}"
echo -e "Manifest: ${BLUE}${MANIFEST_PATH}${NC}"
if [[ ":${PATH}:" != *":${WRAPPER_DIR}:"* ]]; then
    log_warn "Add ${WRAPPER_DIR} to PATH before running freebuff."
fi
echo -e "${BLUE}[INSTALL_STATUS]${NC} success"
echo -e "${BLUE}[DISTRO]${NC} ${DISTRO}"
echo -e "${BLUE}[WRAPPER_PATH]${NC} ${WRAPPER_PATH}"
echo -e "${BLUE}[MANIFEST_PATH]${NC} ${MANIFEST_PATH}"
