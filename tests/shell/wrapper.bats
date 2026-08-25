#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    WRAPPER="${REPO_ROOT}/scripts/freebuff-wrapper.sh"
    TEST_HOME="${BATS_TEST_TMPDIR}/home"
    STUB_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${TEST_HOME}" "${STUB_BIN}"
    cat >"${STUB_BIN}/proot-distro" <<'STUB'
#!/usr/bin/env bash
if [[ -n "${STUB_MARKER:-}" ]]; then
    printf 'called\n' >"${STUB_MARKER}"
fi
if [[ -n "${STUB_LOGIN_URL:-}" ]]; then
    bridge_file=''
    for argument in "$@"; do
        case "${argument}" in
            */.cache/freebuff-termux/sessions/session.*/login-url)
                bridge_file="${argument}"
                break
                ;;
        esac
    done
    [[ -n "${bridge_file}" ]] || exit 91
    printf '%s\n' "${STUB_LOGIN_URL}" >"${bridge_file}"
    sleep 1
    exit 0
fi
if [[ "${STUB_MODE:-}" == "ignore-term" ]]; then
    printf '%s\n' "$$" >"${STUB_PID_FILE}"
    trap '' TERM HUP
    if [[ -n "${STUB_GRANDCHILD_PID_FILE:-}" ]]; then
        (
            trap '' TERM HUP
            printf '%s\n' "${BASHPID}" >"${STUB_GRANDCHILD_PID_FILE}"
            sleep 2
            printf 'orphan\n' >"${STUB_ORPHAN_SENTINEL}"
            while true; do sleep 1; done
        ) &
    fi
    while true; do
        sleep 1
    done
fi
exit "${STUB_EXIT_CODE:-0}"
STUB
    chmod +x "${STUB_BIN}/proot-distro"
    if ! command -v setsid >/dev/null 2>&1; then
        cat >"${STUB_BIN}/setsid" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "--wait" ]]; then shift; fi
exec "$@"
STUB
        chmod +x "${STUB_BIN}/setsid"
    fi
}

teardown() {
    local pid
    if [[ "${STUB_PID:-}" =~ ^[0-9]+$ ]]; then
        kill -KILL -- "-${STUB_PID}" 2>/dev/null || true
    fi
    for pid in "${WRAPPER_PID:-}" "${STUB_PID:-}" "${GRANDCHILD_PID:-}"; do
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            kill -KILL "${pid}" 2>/dev/null || true
        fi
    done
}

@test "wrapper preserves the child exit code and removes session state" {
    run env HOME="${TEST_HOME}" \
        PATH="${STUB_BIN}:${PATH}" \
        STUB_EXIT_CODE=23 \
        bash "${WRAPPER}"

    [ "${status}" -eq 23 ]
    session_root="${TEST_HOME}/.cache/freebuff-termux/sessions"
    if [[ -d "${session_root}" ]]; then
        [ -z "$(find "${session_root}" -mindepth 1 -print -quit)" ]
    fi
}

@test "wrapper rejects an unsafe distro before spawning proot-distro" {
    marker="${BATS_TEST_TMPDIR}/proot-called"
    mkdir -p "${TEST_HOME}/.config/freebuff-termux"
    printf '%s\n' '--help' >"${TEST_HOME}/.config/freebuff-termux/distro"

    run env HOME="${TEST_HOME}" \
        PATH="${STUB_BIN}:${PATH}" \
        STUB_MARKER="${marker}" \
        bash "${WRAPPER}"

    [ "${status}" -eq 2 ]
    [ ! -e "${marker}" ]
}

@test "wrapper rejects an unsafe kill grace before spawning proot-distro" {
    local marker="${BATS_TEST_TMPDIR}/proot-called"

    run env HOME="${TEST_HOME}" \
        PATH="${STUB_BIN}:${PATH}" \
        STUB_MARKER="${marker}" \
        FREEBUFF_KILL_GRACE_SECONDS='0;touch-pwned' \
        bash "${WRAPPER}"

    [ "${status}" -eq 2 ]
    [ ! -e "${marker}" ]
}

@test "concurrent wrappers never cross-deliver session login URLs" {
    local capture_one="${BATS_TEST_TMPDIR}/url-one"
    local capture_two="${BATS_TEST_TMPDIR}/url-two"
    cat >"${STUB_BIN}/termux-open-url" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$1" >"${STUB_URL_CAPTURE:?}"
STUB
    chmod +x "${STUB_BIN}/termux-open-url"

    env HOME="${TEST_HOME}" \
        PATH="${STUB_BIN}:${PATH}" \
        STUB_LOGIN_URL='https://example.invalid/session-one' \
        STUB_URL_CAPTURE="${capture_one}" \
        bash "${WRAPPER}" >"${BATS_TEST_TMPDIR}/wrapper-one-output" 2>&1 &
    local wrapper_one=$!
    env HOME="${TEST_HOME}" \
        PATH="${STUB_BIN}:${PATH}" \
        STUB_LOGIN_URL='https://example.invalid/session-two' \
        STUB_URL_CAPTURE="${capture_two}" \
        bash "${WRAPPER}" >"${BATS_TEST_TMPDIR}/wrapper-two-output" 2>&1 &
    local wrapper_two=$!

    set +e
    wait "${wrapper_one}"
    local status_one=$?
    wait "${wrapper_two}"
    local status_two=$?
    set -e

    [ "${status_one}" -eq 0 ]
    [ "${status_two}" -eq 0 ]
    [ "$(cat "${capture_one}")" = 'https://example.invalid/session-one' ]
    [ "$(cat "${capture_two}")" = 'https://example.invalid/session-two' ]
    local session_root="${TEST_HOME}/.cache/freebuff-termux/sessions"
    if [[ -d "${session_root}" ]]; then
        [ -z "$(find "${session_root}" -mindepth 1 -print -quit)" ]
    fi
}

@test "wrapper escalates SIGTERM and reaps a child that ignores it" {
    [[ "$(uname -s)" == Linux ]] || skip "real setsid process groups require Linux"
    command -v setsid >/dev/null 2>&1 || skip "setsid is unavailable on this host"
    local pid_file="${BATS_TEST_TMPDIR}/proot-pid"
    local grandchild_pid_file="${BATS_TEST_TMPDIR}/grandchild-pid"
    local orphan_sentinel="${BATS_TEST_TMPDIR}/orphan-sentinel"
    env HOME="${TEST_HOME}" \
        PATH="${STUB_BIN}:${PATH}" \
        FREEBUFF_KILL_GRACE_SECONDS=0 \
        STUB_MODE=ignore-term \
        STUB_PID_FILE="${pid_file}" \
        STUB_GRANDCHILD_PID_FILE="${grandchild_pid_file}" \
        STUB_ORPHAN_SENTINEL="${orphan_sentinel}" \
        bash "${WRAPPER}" >"${BATS_TEST_TMPDIR}/wrapper-output" 2>&1 &
    WRAPPER_PID=$!

    local attempt
    for ((attempt = 0; attempt < 50; attempt += 1)); do
        [[ -f "${pid_file}" && -f "${grandchild_pid_file}" ]] && break
        sleep 0.1
    done
    [ -f "${pid_file}" ]
    [ -f "${grandchild_pid_file}" ]
    STUB_PID="$(<"${pid_file}")"
    GRANDCHILD_PID="$(<"${grandchild_pid_file}")"

    kill -TERM "${WRAPPER_PID}"
    set +e
    wait "${WRAPPER_PID}"
    local wrapper_status=$?
    set -e
    WRAPPER_PID=''

    [ "${wrapper_status}" -eq 143 ]
    ! kill -0 "${STUB_PID}" 2>/dev/null
    ! kill -0 "${GRANDCHILD_PID}" 2>/dev/null
    sleep 2.1
    [ ! -e "${orphan_sentinel}" ]
    STUB_PID=''
    GRANDCHILD_PID=''
    local session_root="${TEST_HOME}/.cache/freebuff-termux/sessions"
    if [[ -d "${session_root}" ]]; then
        [ -z "$(find "${session_root}" -mindepth 1 -print -quit)" ]
    fi
}
