#!/data/data/com.termux/files/usr/bin/bash
# FreeBuff Termux lifecycle manager
set -euo pipefail
umask 077

STATE_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/freebuff-termux"
MANIFEST_PATH="${STATE_DIR}/install-manifest"
WRAPPER_DIR="${HOME}/.local/bin"
EXPECTED_WRAPPER_PATH="${WRAPPER_DIR}/freebuff"
EXPECTED_MANAGER_PATH="${WRAPPER_DIR}/freebuff-termux"
EXPECTED_CONFIG_PATH="${XDG_CONFIG_HOME:-${HOME}/.config}/freebuff-termux/distro"
DEFAULT_NODE_VERSION='v22.17.1'
DEFAULT_FREEBUFF_VERSION='0.0.152'

log_info() { echo "[INFO] $1"; }
log_warn() { echo "[WARN] $1" >&2; }
log_error() { echo "[ERROR] $1" >&2; }

manifest_value() {
    local key="$1"
    awk -v key="${key}" 'index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }' "${MANIFEST_PATH}"
}

require_manifest() {
    if [[ ! -f "${MANIFEST_PATH}" ]] || [[ -L "${MANIFEST_PATH}" ]]; then
        log_error "Install manifest is missing or unsafe."
        return 2
    fi
    if [[ "$(manifest_value schema)" != "2" ]]; then
        log_error "Unsupported install manifest schema."
        return 2
    fi
}

validate_identifier() {
    local value="$1" label="$2"
    if [[ ! "${value}" =~ ^[[:alnum:]][[:alnum:]._-]{0,63}$ ]] || [[ "${value}" == "." ]] || [[ "${value}" == ".." ]]; then
        log_error "Invalid ${label} in install manifest."
        return 2
    fi
}

validate_pinned_image() {
    local value="$1"
    if [[ ${#value} -gt 512 ]] || [[ ! "${value}" =~ ^[a-z0-9][a-z0-9._:/-]*@sha256:[0-9a-f]{64}$ ]]; then
        log_error "Invalid PRoot image in install manifest."
        return 2
    fi
}

validate_manifest_contract() {
    local distro node_version node_tarball_sha256 freebuff_version freebuff_tarball_sha512 proot_image rootfs
    local key value
    distro="$(manifest_value distro)"
    node_version="$(manifest_value node_version)"
    node_tarball_sha256="$(manifest_value node_tarball_sha256)"
    freebuff_version="$(manifest_value freebuff_version)"
    freebuff_tarball_sha512="$(manifest_value freebuff_tarball_sha512)"
    proot_image="$(manifest_value proot_image)"
    validate_identifier "${distro}" distro
    validate_identifier "${node_version}" "Node version"
    validate_identifier "${freebuff_version}" "FreeBuff version"
    validate_pinned_image "${proot_image}"
    if [[ -n "${node_tarball_sha256}" ]] && [[ ! "${node_tarball_sha256}" =~ ^[0-9a-f]{64}$ ]]; then
        log_error "Install manifest contains an invalid Node archive checksum."
        return 2
    fi
    if [[ "${node_version}" != "${DEFAULT_NODE_VERSION}" ]] && [[ -z "${node_tarball_sha256}" ]]; then
        log_error "Custom Node runtime is missing its archive checksum."
        return 2
    fi
    if [[ -n "${freebuff_tarball_sha512}" ]] && [[ ! "${freebuff_tarball_sha512}" =~ ^[0-9a-f]{128}$ ]]; then
        log_error "Install manifest contains an invalid FreeBuff archive checksum."
        return 2
    fi
    if [[ "${freebuff_version}" != "${DEFAULT_FREEBUFF_VERSION}" ]] && [[ -z "${freebuff_tarball_sha512}" ]]; then
        log_error "Custom FreeBuff runtime is missing its archive checksum."
        return 2
    fi

    rootfs="${PREFIX:-/data/data/com.termux/files/usr}/var/lib/proot-distro/containers/${distro}/rootfs"
    if [[ "$(manifest_value wrapper_path)" != "${EXPECTED_WRAPPER_PATH}" ]] \
        || [[ "$(manifest_value manager_path)" != "${EXPECTED_MANAGER_PATH}" ]] \
        || [[ "$(manifest_value config_path)" != "${EXPECTED_CONFIG_PATH}" ]] \
        || [[ "$(manifest_value bridge_path)" != "${rootfs}/usr/local/bin/xdg-open" ]]; then
        log_error "Install manifest contains an invalid managed path."
        return 2
    fi

    for key in wrapper_sha256 manager_sha256 bridge_sha256 config_sha256; do
        value="$(manifest_value "${key}")"
        if [[ ! "${value}" =~ ^[0-9a-f]{64}$ ]]; then
            log_error "Install manifest contains an invalid managed checksum."
            return 2
        fi
    done
}

print_invalid_doctor() {
    printf '{"schemaVersion":2,"status":"invalid","distro":"unknown","checks":[]}\n'
}

hash_matches() {
    local path="$1" expected="$2"
    [[ -f "${path}" ]] && [[ ! -L "${path}" ]] \
        && [[ "$(sha256sum "${path}" | awk '{print $1}')" == "${expected}" ]]
}

declare -a CHECK_IDS=()
declare -a CHECK_VALUES=()
CHECK_FAILURES=0

record_check() {
    local id="$1"
    shift
    CHECK_IDS+=("${id}")
    if "$@" >/dev/null 2>&1; then
        CHECK_VALUES+=(true)
    else
        CHECK_VALUES+=(false)
        CHECK_FAILURES=$((CHECK_FAILURES + 1))
    fi
}

doctor() {
    local output_json=0
    if [[ "${1:-}" == "--json" ]]; then output_json=1; fi

    if [[ ${output_json} -eq 1 ]]; then
        if ! require_manifest 2>/dev/null; then
            print_invalid_doctor
            return 2
        fi
    elif ! require_manifest; then
        return 2
    fi

    local distro wrapper_path wrapper_sha manager_path manager_sha bridge_path bridge_sha
    local config_path config_sha node_version freebuff_version proot_image rootfs
    distro="$(manifest_value distro)"
    node_version="$(manifest_value node_version)"
    freebuff_version="$(manifest_value freebuff_version)"
    proot_image="$(manifest_value proot_image)"
    if [[ ${output_json} -eq 1 ]]; then
        if ! validate_manifest_contract 2>/dev/null; then
            print_invalid_doctor
            return 2
        fi
    else
        validate_manifest_contract
    fi

    wrapper_path="$(manifest_value wrapper_path)"
    wrapper_sha="$(manifest_value wrapper_sha256)"
    manager_path="$(manifest_value manager_path)"
    manager_sha="$(manifest_value manager_sha256)"
    bridge_path="$(manifest_value bridge_path)"
    bridge_sha="$(manifest_value bridge_sha256)"
    config_path="$(manifest_value config_path)"
    config_sha="$(manifest_value config_sha256)"
    rootfs="${PREFIX:-/data/data/com.termux/files/usr}/var/lib/proot-distro/containers/${distro}/rootfs"

    CHECK_IDS=()
    CHECK_VALUES=()
    CHECK_FAILURES=0
    record_check manifest test -f "${MANIFEST_PATH}"
    record_check wrapper hash_matches "${wrapper_path}" "${wrapper_sha}"
    record_check manager hash_matches "${manager_path}" "${manager_sha}"
    record_check bridge hash_matches "${bridge_path}" "${bridge_sha}"
    record_check config hash_matches "${config_path}" "${config_sha}"
    record_check distro_rootfs test -d "${rootfs}"
    record_check node test -x "${rootfs}/opt/freebuff-termux/node-${node_version}/bin/node"
    record_check freebuff test -x "${rootfs}/opt/freebuff-termux/freebuff-${freebuff_version}/bin/freebuff"

    local status='ok'
    if [[ ${CHECK_FAILURES} -gt 0 ]]; then status='degraded'; fi
    if [[ ${output_json} -eq 1 ]]; then
        printf '{"schemaVersion":2,"status":"%s","distro":"%s","checks":[' "${status}" "${distro}"
        local index
        for ((index = 0; index < ${#CHECK_IDS[@]}; index++)); do
            if [[ ${index} -gt 0 ]]; then printf ','; fi
            printf '{"id":"%s","ok":%s}' "${CHECK_IDS[index]}" "${CHECK_VALUES[index]}"
        done
        printf ']}\n'
    else
        local index
        echo "FreeBuff Termux doctor (${distro})"
        for ((index = 0; index < ${#CHECK_IDS[@]}; index++)); do
            printf '  [%s] %s\n' "${CHECK_VALUES[index]}" "${CHECK_IDS[index]}"
        done
        echo "Status: ${status}"
    fi
    [[ ${CHECK_FAILURES} -eq 0 ]]
}

remove_if_managed() {
    local path="$1" expected="$2" label="$3"
    if [[ ! -e "${path}" ]] && [[ ! -L "${path}" ]]; then
        return 0
    fi
    if hash_matches "${path}" "${expected}"; then
        rm -f -- "${path}"
        return 0
    fi
    log_warn "Preserving modified ${label}: ${path}"
    return 1
}

uninstall_managed() {
    require_manifest
    validate_manifest_contract
    local conflicts=0
    remove_if_managed "$(manifest_value bridge_path)" "$(manifest_value bridge_sha256)" bridge || conflicts=1
    remove_if_managed "$(manifest_value wrapper_path)" "$(manifest_value wrapper_sha256)" wrapper || conflicts=1
    remove_if_managed "$(manifest_value config_path)" "$(manifest_value config_sha256)" config || conflicts=1
    remove_if_managed "$(manifest_value manager_path)" "$(manifest_value manager_sha256)" manager || conflicts=1

    if [[ ${conflicts} -eq 0 ]]; then
        rm -f -- "${MANIFEST_PATH}"
        log_info "Managed files removed. Distro, runtime, projects, and credentials were preserved."
        return 0
    fi
    log_warn "Some modified files were preserved; manifest retained for recovery."
    return 1
}

repair_install() {
    require_manifest
    validate_manifest_contract
    local source_path installer installer_sha distro proot_image
    local node_version node_tarball_sha256 freebuff_version freebuff_tarball_sha512
    source_path="$(manifest_value source_path)"
    installer="${source_path}/scripts/install.sh"
    installer_sha="$(manifest_value installer_sha256)"
    distro="$(manifest_value distro)"
    proot_image="$(manifest_value proot_image)"
    node_version="$(manifest_value node_version)"
    node_tarball_sha256="$(manifest_value node_tarball_sha256)"
    freebuff_version="$(manifest_value freebuff_version)"
    freebuff_tarball_sha512="$(manifest_value freebuff_tarball_sha512)"
    validate_identifier "${distro}" distro
    validate_identifier "${node_version}" "Node version"
    validate_identifier "${freebuff_version}" "FreeBuff version"
    validate_pinned_image "${proot_image}"
    if ! hash_matches "${installer}" "${installer_sha}"; then
        log_error "Pinned repair installer is missing or modified."
        return 2
    fi
    FREEBUFF_PROOT_IMAGE="${proot_image}" \
        FREEBUFF_NODE_VERSION="${node_version}" \
        FREEBUFF_NODE_TARBALL_SHA256="${node_tarball_sha256}" \
        FREEBUFF_VERSION="${freebuff_version}" \
        FREEBUFF_TARBALL_SHA512="${freebuff_tarball_sha512}" \
        "${installer}" "${distro}"
}

update_install() {
    require_manifest
    validate_manifest_contract
    local ref="${1:-}" expected_commit="${2:-}" artifact_sha="${3:-}"
    local source_path bootstrap bootstrap_sha distro proot_image
    if [[ -z "${ref}" ]]; then
        log_error "Usage: freebuff-termux update <tag-or-full-sha> [expected-commit] [artifact-sha256]"
        return 2
    fi
    source_path="$(manifest_value source_path)"
    bootstrap="${source_path}/scripts/remote-install.sh"
    bootstrap_sha="$(manifest_value bootstrap_sha256)"
    distro="$(manifest_value distro)"
    proot_image="$(manifest_value proot_image)"
    validate_identifier "${distro}" distro
    validate_pinned_image "${proot_image}"
    if ! hash_matches "${bootstrap}" "${bootstrap_sha}"; then
        log_error "Pinned update bootstrap is missing or modified."
        return 2
    fi
    FREEBUFF_PROOT_IMAGE="${proot_image}" FREEBUFF_TERMUX_REF="${ref}" FREEBUFF_TERMUX_EXPECTED_COMMIT="${expected_commit}" \
        FREEBUFF_TERMUX_ARTIFACT_SHA256="${artifact_sha}" \
        "${bootstrap}" "${distro}"
}

usage() {
    echo "Usage: freebuff-termux {doctor [--json]|repair|update <ref> [commit] [artifact-sha256]|uninstall}"
}

case "${1:-}" in
    doctor)
        shift
        doctor "${1:-}"
        ;;
    repair) repair_install ;;
    update)
        shift
        update_install "${1:-}" "${2:-}" "${3:-}"
        ;;
    uninstall) uninstall_managed ;;
    *)
        usage
        exit 2
        ;;
esac
