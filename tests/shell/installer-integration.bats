#!/usr/bin/env bats

setup() {
    [[ "${FREEBUFF_RUN_INSTALLER_INTEGRATION:-0}" == "1" ]] \
        || skip "full installer integration requires explicit opt-in"
    [[ "${EUID}" -eq 0 ]] || skip "full installer integration requires an isolated root container"

    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    INSTALLER="${REPO_ROOT}/scripts/install.sh"
    TERMUX_FILES_ROOT="/data/data/com.termux.freebuff-test-${BATS_TEST_NUMBER}-$$/files"
    TEST_PREFIX="${TERMUX_FILES_ROOT}/usr"
    TEST_HOME="${BATS_TEST_TMPDIR}/home"
    STUB_BIN="${BATS_TEST_TMPDIR}/bin"
    ROOTFS="${TEST_PREFIX}/var/lib/proot-distro/containers/ubuntu/rootfs"
    WRAPPER="${TEST_HOME}/.local/bin/freebuff"
    MANAGER="${TEST_HOME}/.local/bin/freebuff-termux"
    CONFIG="${TEST_HOME}/.config/freebuff-termux/distro"
    STATE_DIR="${TEST_HOME}/.local/share/freebuff-termux"
    MANIFEST="${STATE_DIR}/install-manifest"
    BRIDGE="${ROOTFS}/usr/local/bin/xdg-open"
    NODE_LINK="${ROOTFS}/opt/freebuff-termux/current-node"
    FREEBUFF_LINK="${ROOTFS}/opt/freebuff-termux/current-freebuff"
    TRANSACTION="${STATE_DIR}/install-transaction"
    SENTINEL="${TEST_HOME}/project-sentinel"

    mkdir -p \
        "${TEST_PREFIX}/tmp" \
        "${ROOTFS}/usr/local/bin" \
        "${ROOTFS}/opt/freebuff-termux/node-v22.17.1/bin" \
        "${ROOTFS}/opt/freebuff-termux/freebuff-0.0.152/bin" \
        "$(dirname "${WRAPPER}")" \
        "$(dirname "${CONFIG}")" \
        "${STATE_DIR}" \
        "${STUB_BIN}"

    printf '#!/usr/bin/env sh\nexit 0\n' >"${ROOTFS}/opt/freebuff-termux/node-v22.17.1/bin/node"
    printf '#!/usr/bin/env sh\nexit 0\n' >"${ROOTFS}/opt/freebuff-termux/freebuff-0.0.152/bin/freebuff"
    chmod +x \
        "${ROOTFS}/opt/freebuff-termux/node-v22.17.1/bin/node" \
        "${ROOTFS}/opt/freebuff-termux/freebuff-0.0.152/bin/freebuff"
    ln -s '/opt/freebuff-termux/node-old' "${NODE_LINK}"
    ln -s '/opt/freebuff-termux/freebuff-old' "${FREEBUFF_LINK}"

    printf 'old-wrapper\n' >"${WRAPPER}"
    printf 'old-manager\n' >"${MANAGER}"
    printf 'old-bridge\n' >"${BRIDGE}"
    printf 'ubuntu\n' >"${CONFIG}"
    printf 'preserve-user-project\n' >"${SENTINEL}"

    local wrapper_sha manager_sha bridge_sha config_sha
    wrapper_sha="$(sha256sum "${WRAPPER}" | awk '{print $1}')"
    manager_sha="$(sha256sum "${MANAGER}" | awk '{print $1}')"
    bridge_sha="$(sha256sum "${BRIDGE}" | awk '{print $1}')"
    config_sha="$(sha256sum "${CONFIG}" | awk '{print $1}')"
    cat >"${MANIFEST}" <<MANIFEST
schema=2
distro=ubuntu
proot_image=ubuntu@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517
node_version=v0-old
freebuff_version=0.0.0-old
source_ref=old
source_commit=1111111111111111111111111111111111111111
source_path=/old/source
installer_sha256=1111111111111111111111111111111111111111111111111111111111111111
bootstrap_sha256=2222222222222222222222222222222222222222222222222222222222222222
wrapper_path=${WRAPPER}
wrapper_sha256=${wrapper_sha}
manager_path=${MANAGER}
manager_sha256=${manager_sha}
bridge_path=${BRIDGE}
bridge_sha256=${bridge_sha}
config_path=${CONFIG}
config_sha256=${config_sha}
node_root=/opt/freebuff-termux/node-old
freebuff_root=/opt/freebuff-termux/freebuff-old
MANIFEST
    OLD_MANIFEST="$(cat "${MANIFEST}")"

    cat >"${STUB_BIN}/dpkg" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == '--print-architecture' ]]; then
    printf 'amd64\n'
fi
exit 0
STUB
    cat >"${STUB_BIN}/pkg" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    cat >"${STUB_BIN}/proot-distro" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
rootfs="${STUB_ROOTFS:?}"
[[ "${1:-}" == 'login' ]] || exit 0
while [[ $# -gt 0 ]] && [[ "${1}" != '-c' ]]; do shift; done
[[ "${1:-}" == '-c' ]] || exit 98
shift
command_text="${1:-}"
shift
[[ "${1:-}" == '--' ]] && shift
case "${command_text}" in
    *'test -x "$1/bin/freebuff"'*)
        test -x "${rootfs}${1}/bin/freebuff"
        ;;
    *'ln -sfn "$node_root"'*)
        node_root="$1"
        freebuff_root="$2"
        mkdir -p "${rootfs}/opt/freebuff-termux"
        ln -sfn "${node_root}" "${rootfs}/opt/freebuff-termux/current-node"
        ln -sfn "${freebuff_root}" "${rootfs}/opt/freebuff-termux/current-freebuff"
        ;;
    *'remove_owned_link()'*)
        exit 0
        ;;
    *)
        printf 'unexpected proot command: %s\n' "${command_text}" >&2
        exit 99
        ;;
esac
STUB
    chmod +x "${STUB_BIN}/dpkg" "${STUB_BIN}/pkg" "${STUB_BIN}/proot-distro"
}

teardown() {
    if [[ "${TERMUX_FILES_ROOT:-}" =~ ^/data/data/com\.termux\.freebuff-test-[0-9]+-[0-9]+/files$ ]]; then
        rm -rf -- "${TERMUX_FILES_ROOT}"
    fi
}

run_installer() {
    local failpoint="$1"
    env \
        HOME="${TEST_HOME}" \
        PREFIX="${TEST_PREFIX}" \
        TMPDIR="${TEST_PREFIX}/tmp" \
        PATH="${STUB_BIN}:/usr/bin:/bin" \
        STUB_ROOTFS="${ROOTFS}" \
        FREEBUFF_TERMUX_SOURCE_COMMIT=2222222222222222222222222222222222222222 \
        FREEBUFF_INSTALL_TEST_FAILPOINT="${failpoint}" \
        /bin/bash "${INSTALLER}" ubuntu
}

mark_verified_runtime_roots() {
    cat >"${ROOTFS}/opt/freebuff-termux/node-v22.17.1/.freebuff-termux-runtime" <<'MARKER'
schema=1
kind=node
version=v22.17.1
archive_sha256=cfb6ac0cf339825fe36efd1f18a79016b02aca19fbfa6c9547c57e27dc09f6ea
MARKER
    cat >"${ROOTFS}/opt/freebuff-termux/freebuff-0.0.152/.freebuff-termux-runtime" <<'MARKER'
schema=1
kind=freebuff
version=0.0.152
archive_sha512=a63c9383e94a2501cda74df90a147080c6bd60942132afdec44ebdb465b362e6847cf9786a26aec8b00b7e8b11f571c346ecad7fbf5fd98b269edf35e8393e25
MARKER
}

assert_old_managed_set() {
    [ ! -e "${TRANSACTION}" ]
    [ "$(cat "${WRAPPER}")" = 'old-wrapper' ]
    [ "$(cat "${MANAGER}")" = 'old-manager' ]
    [ "$(cat "${BRIDGE}")" = 'old-bridge' ]
    [ "$(cat "${CONFIG}")" = 'ubuntu' ]
    [ "$(cat "${MANIFEST}")" = "${OLD_MANIFEST}" ]
    [ "$(readlink "${NODE_LINK}")" = '/opt/freebuff-termux/node-old' ]
    [ "$(readlink "${FREEBUFF_LINK}")" = '/opt/freebuff-termux/freebuff-old' ]
    [ "$(cat "${SENTINEL}")" = 'preserve-user-project' ]
}

@test "refuses pre-existing runtime roots that are neither manifest-owned nor verified" {
    run run_installer ''

    [ "${status}" -eq 1 ]
    [[ "${output}" == *'Refusing unowned or unverified Node runtime root'* ]]
    [ ! -e "${TRANSACTION}" ]
    [ "$(cat "${SENTINEL}")" = 'preserve-user-project' ]
}

@test "full installer recovers every managed target after each transactional hard crash" {
    mark_verified_runtime_roots
    local stage
    for stage in \
        after_backup \
        after_first_asset_commit \
        before_manifest_commit \
        after_manifest_commit \
        before_backup_cleanup; do
        run run_installer "${stage}:hard"
        [ "${status}" -eq 137 ]
        [ -d "${TRANSACTION}" ]

        run run_installer 'after_backup'
        [ "${status}" -eq 97 ]
        assert_old_managed_set
    done
}

@test "full installer rolls back every managed target after each transactional TERM" {
    mark_verified_runtime_roots
    local stage
    for stage in \
        after_backup \
        after_first_asset_commit \
        before_manifest_commit \
        after_manifest_commit \
        before_backup_cleanup; do
        run run_installer "${stage}:term"
        [ "${status}" -eq 143 ]
        assert_old_managed_set
    done
}
