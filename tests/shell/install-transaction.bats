#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    LIBRARY="${REPO_ROOT}/scripts/lib/install-transaction.sh"
    TEST_ROOT="${BATS_TEST_TMPDIR}/transaction"
    TXN_DIR="${TEST_ROOT}/state/install-transaction"
    TARGET_ONE="${TEST_ROOT}/managed/freebuff"
    TARGET_TWO="${TEST_ROOT}/managed/freebuff-termux"
    SENTINEL="${TEST_ROOT}/managed/user-project.txt"
    mkdir -p "$(dirname "${TARGET_ONE}")"
    printf 'old-wrapper\n' >"${TARGET_ONE}"
    printf 'old-manager\n' >"${TARGET_TWO}"
    printf 'preserve\n' >"${SENTINEL}"
}

@test "recovers the complete old file set after a hard exit" {
    run bash -c '
        set -e
        source "$1"
        install_transaction_begin "$2" ubuntu "$3" "$4"
        printf "new-wrapper\n" >"$3"
        printf "new-manager\n" >"$4"
        exit 99
    ' -- "${LIBRARY}" "${TXN_DIR}" "${TARGET_ONE}" "${TARGET_TWO}"
    [ "${status}" -eq 99 ]

    run bash -c '
        set -e
        source "$1"
        install_transaction_recover "$2" ubuntu "$3" "$4"
    ' -- "${LIBRARY}" "${TXN_DIR}" "${TARGET_ONE}" "${TARGET_TWO}"
    [ "${status}" -eq 0 ]
    [ "$(cat "${TARGET_ONE}")" = 'old-wrapper' ]
    [ "$(cat "${TARGET_TWO}")" = 'old-manager' ]
    [ "$(cat "${SENTINEL}")" = 'preserve' ]
    [ ! -e "${TXN_DIR}" ]
}

@test "commit keeps the complete new file set and removes transaction state" {
    run bash -c '
        set -e
        source "$1"
        install_transaction_begin "$2" ubuntu "$3" "$4"
        printf "new-wrapper\n" >"$3"
        printf "new-manager\n" >"$4"
        install_transaction_commit "$2"
    ' -- "${LIBRARY}" "${TXN_DIR}" "${TARGET_ONE}" "${TARGET_TWO}"
    [ "${status}" -eq 0 ]
    [ "$(cat "${TARGET_ONE}")" = 'new-wrapper' ]
    [ "$(cat "${TARGET_TWO}")" = 'new-manager' ]
    [ "$(cat "${SENTINEL}")" = 'preserve' ]
    [ ! -e "${TXN_DIR}" ]
}

@test "recovery refuses a mismatched distro context without touching files" {
    run bash -c '
        set -e
        source "$1"
        install_transaction_begin "$2" ubuntu "$3" "$4"
        printf "new-wrapper\n" >"$3"
    ' -- "${LIBRARY}" "${TXN_DIR}" "${TARGET_ONE}" "${TARGET_TWO}"
    [ "${status}" -eq 0 ]

    run bash -c '
        source "$1"
        install_transaction_recover "$2" debian "$3" "$4"
    ' -- "${LIBRARY}" "${TXN_DIR}" "${TARGET_ONE}" "${TARGET_TWO}"
    [ "${status}" -ne 0 ]
    [ "$(cat "${TARGET_ONE}")" = 'new-wrapper' ]
    [ "$(cat "${TARGET_TWO}")" = 'old-manager' ]
    [ "$(cat "${SENTINEL}")" = 'preserve' ]
    [ -d "${TXN_DIR}" ]
}

@test "begin removes stale pre-commit staging directories" {
    local stale="${TXN_DIR}.tmp.stale"
    mkdir -p "${stale}"
    printf 'stale\n' >"${stale}/partial"

    run bash -c '
        set -e
        source "$1"
        install_transaction_begin "$2" ubuntu "$3" "$4"
        install_transaction_commit "$2"
    ' -- "${LIBRARY}" "${TXN_DIR}" "${TARGET_ONE}" "${TARGET_TWO}"
    [ "${status}" -eq 0 ]
    [ ! -e "${stale}" ]
    [ "$(cat "${SENTINEL}")" = 'preserve' ]
}
