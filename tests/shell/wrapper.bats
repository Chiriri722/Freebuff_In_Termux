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
if [[ "${STUB_MODE:-}" == "stdin" ]]; then
    if [[ "${STUB_REQUIRE_TTY:-0}" == 1 ]]; then [[ -t 0 ]] || exit 93; fi
    IFS= read -r line || exit 92
    printf 'input=%s\n' "${line}"
    exit 0
fi
if [[ "${STUB_MODE:-}" == "cwd" ]]; then
    while [[ $# -gt 0 && "$1" != -c ]]; do shift; done
    shift
    script="$1"
    shift
    /bin/bash -c 'exec() { printf "RAN:%s\n" "$PWD"; printf "ARG:%s\n" "$@"; }; '"${script}" "$@"
    exit $?
fi
if [[ "${STUB_MODE:-}" == "normal-descendant" ]]; then
    (trap '' TERM HUP; printf '%s\n' "${BASHPID}" >"${STUB_GRANDCHILD_PID_FILE}";
      sleep 1; printf orphan >"${STUB_ORPHAN_SENTINEL}"; sleep 10) </dev/null >/dev/null 2>&1 &
    exit "${STUB_EXIT_CODE:-0}"
fi
if [[ -n "${STUB_LOGIN_URL:-}" ]]; then
    bridge_file=''
    for argument in "$@"; do
        case "${argument}" in
            */.cache/freebuff-termux/sessions/session.*/login-url)
                bridge_file="${HOME}${argument#/root}"
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

@test "wrapper forwards piped stdin" {
    printf 'hello interactive input\n' >"${BATS_TEST_TMPDIR}/stdin"
    run env HOME="${TEST_HOME}" PATH="${STUB_BIN}:${PATH}" STUB_MODE=stdin \
        bash "${WRAPPER}" <"${BATS_TEST_TMPDIR}/stdin"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *'input=hello interactive input'* ]]
}

@test "wrapper preserves a PTY stdin descriptor" {
    command -v python3 >/dev/null 2>&1 || skip "requires Python PTY fixture"
    run env HOME="${TEST_HOME}" PATH="${STUB_BIN}:${PATH}" STUB_MODE=stdin STUB_REQUIRE_TTY=1 \
        python3 - "${WRAPPER}" <<'PYTHON'
import os, pty, subprocess, sys
master, slave = pty.openpty()
try:
    os.write(master, b'hello terminal\n')
    result = subprocess.run(['/bin/bash', sys.argv[1]], stdin=slave, capture_output=True, timeout=10)
    sys.stdout.buffer.write(result.stdout)
    sys.stderr.buffer.write(result.stderr)
    sys.exit(result.returncode)
finally:
    os.close(master)
    os.close(slave)
PYTHON
    [ "${status}" -eq 0 ]
    [[ "${output}" == *'input=hello terminal'* ]]
}

@test "wrapper refuses missing guest CWD and preserves valid CWD and arguments" {
    mkdir -p "${TEST_HOME}/missing-guest-${BATS_TEST_NUMBER}"
    cd "${TEST_HOME}/missing-guest-${BATS_TEST_NUMBER}"
    run env HOME="${TEST_HOME}" PATH="${STUB_BIN}:${PATH}" STUB_MODE=cwd bash "${WRAPPER}"
    [ "${status}" -ne 0 ]
    [[ "${output}" != *RAN:* ]]
    local valid="${BATS_TEST_TMPDIR}/space ' project"
    mkdir -p "${valid}"
    cd "${valid}"
    run env HOME="${TEST_HOME}" PATH="${STUB_BIN}:${PATH}" STUB_MODE=cwd \
        bash "${WRAPPER}" '--help' 'a b' '";$(touch injected)'
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"RAN:${valid}"* ]]
    [[ "${output}" == *'ARG:--help'* && "${output}" == *'ARG:a b'* ]]
    [[ "${output}" == *'ARG:";$(touch injected)'* ]]
}

@test "wrapper cleans surviving descendants on normal and nonzero exit" {
    for code in 0 23; do
        local pid_file="${BATS_TEST_TMPDIR}/descendant-${code}"
        local sentinel="${BATS_TEST_TMPDIR}/sentinel-${code}"
        run env HOME="${TEST_HOME}" PATH="${STUB_BIN}:${PATH}" \
            FREEBUFF_KILL_GRACE_SECONDS=0 STUB_MODE=normal-descendant \
            STUB_EXIT_CODE="${code}" STUB_GRANDCHILD_PID_FILE="${pid_file}" \
            STUB_ORPHAN_SENTINEL="${sentinel}" bash "${WRAPPER}"
        [ "${status}" -eq "${code}" ]
        [ -f "${pid_file}" ]
        GRANDCHILD_PID="$(cat "${pid_file}")"
        sleep 1.2
        [ ! -e "${sentinel}" ]
    done
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
