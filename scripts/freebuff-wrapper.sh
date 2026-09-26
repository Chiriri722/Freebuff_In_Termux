#!/data/data/com.termux/files/usr/bin/bash
# FreeBuff Termux Wrapper — proot-distro 환경에서 freebuff 실행
#
# 핵심 설정:
# - OVERRIDE_PLATFORM=linux: proot 내부에서도 freebuff가 linux-arm64 바이너리를 다운로드
# - PATH: /opt/freebuff-termux 아래의 전용 Node.js+FreeBuff를 우선 사용
# - xdg-open 브리지: 세션별 private 파일로 로그인 URL을 Termux에 전달
set -euo pipefail
umask 077
TERMUX_HOME="${HOME}"
PROOT_HOME="/root"
DISTRO_FILE="${XDG_CONFIG_HOME:-${TERMUX_HOME}/.config}/freebuff-termux/distro"
DISTRO="${FREEBUFF_PROOT_DISTRO:-}"
if [[ -z "${DISTRO}" ]] && [[ -f "${DISTRO_FILE}" ]] && [[ ! -L "${DISTRO_FILE}" ]]; then
    IFS= read -r DISTRO <"${DISTRO_FILE}" || true
fi
DISTRO="${DISTRO:-ubuntu}"
if [[ ! "${DISTRO}" =~ ^[[:alnum:]][[:alnum:]._-]{0,63}$ ]] || [[ "${DISTRO}" == "." ]] || [[ "${DISTRO}" == ".." ]]; then
    echo "freebuff: invalid distro identifier" >&2
    exit 2
fi
KILL_GRACE_SECONDS="${FREEBUFF_KILL_GRACE_SECONDS:-5}"
if [[ ! "${KILL_GRACE_SECONDS}" =~ ^[0-9]+$ ]] || [[ ${KILL_GRACE_SECONDS} -gt 60 ]]; then
    echo "freebuff: FREEBUFF_KILL_GRACE_SECONDS must be an integer from 0 to 60" >&2
    exit 2
fi
if ! command -v setsid >/dev/null 2>&1; then
    echo "freebuff: setsid is required; install the Termux util-linux package" >&2
    exit 2
fi

# PRoot-Distro v5 default mode exposes Android storage automatically.
# Isolated mode plus explicit shared-home preserves home projects while
# keeping shared storage opt-in.
PROOT_LOGIN=(proot-distro login --user root --isolated --shared-home)
if [[ "${FREEBUFF_STORAGE_BIND:-0}" == "1" ]]; then
    PROOT_LOGIN+=(--bind /storage/emulated/0)
fi

CURRENT_DIR="$(pwd)"
if [[ "${CURRENT_DIR}" == "${TERMUX_HOME}" ]] || [[ "${CURRENT_DIR}" == "${TERMUX_HOME}/"* ]]; then
    PROOT_CWD="${PROOT_HOME}${CURRENT_DIR#${TERMUX_HOME}}"
elif [[ "${CURRENT_DIR}" == /storage/* ]]; then
    if [[ "${FREEBUFF_STORAGE_BIND:-0}" != "1" ]]; then
        echo "freebuff: shared storage requires FREEBUFF_STORAGE_BIND=1" >&2
        exit 2
    fi
    PROOT_CWD="${CURRENT_DIR}"
else
    PROOT_CWD="${CURRENT_DIR}"
fi

# ─── 세션별 URL 브리지 ──────────────────────────────────────
MAX_URL_LENGTH=4096
BRIDGE_ROOT="${TERMUX_HOME}/.cache/freebuff-termux/sessions"
mkdir -p "${BRIDGE_ROOT}"
chmod 700 "${BRIDGE_ROOT}"
SESSION_DIR="$(mktemp -d "${BRIDGE_ROOT}/session.XXXXXX")"
chmod 700 "${SESSION_DIR}"
URL_BRIDGE_FILE="${SESSION_DIR}/login-url"
GUEST_URL_BRIDGE_FILE="${PROOT_HOME}/.cache/freebuff-termux/sessions/${SESSION_DIR##*/}/login-url"

is_valid_login_url() {
    local url="$1"
    [[ ${#url} -le ${MAX_URL_LENGTH} ]] || return 1
    case "${url}" in
        http://* | https://*) ;;
        *) return 1 ;;
    esac
    [[ ! "${url}" =~ [[:cntrl:]] ]]
}

# ─── 백그라운드 URL 감시자 ───────────────────────────────────
WRAPPER_PID=$$
url_watcher() {
    while kill -0 "${WRAPPER_PID}" 2>/dev/null && [[ -d "${SESSION_DIR}" ]]; do
        if [[ -f "${URL_BRIDGE_FILE}" ]]; then
            local url claimed_file
            claimed_file="${SESSION_DIR}/login-url.claimed.$$"
            if mv "${URL_BRIDGE_FILE}" "${claimed_file}" 2>/dev/null; then
                url=$(cat "${claimed_file}" 2>/dev/null || true)
                rm -f "${claimed_file}" 2>/dev/null || true
            else
                url=""
            fi
            if [[ -n "${url}" ]] && is_valid_login_url "${url}"; then
                echo -e "\n\033[0;34m[INFO]\033[0m Login URL detected. Delivering to browser..."
                # 1단계: termux-open-url (브라우저 자동 열기)
                termux-open-url "${url}" 2>/dev/null && {
                    echo -e "\033[0;32m[OK]\033[0m Browser opened automatically."
                } || {
                    # 2단계: termux-clipboard-set (클립보드에 URL 복사)
                    echo -e "\033[0;33m[WARN]\033[0m Browser auto-open failed. Trying clipboard..."
                    termux-clipboard-set "${url}" 2>/dev/null && {
                        echo -e "\033[0;32m[OK]\033[0m URL copied to clipboard. Paste in browser."
                    } || {
                        if [[ "${FREEBUFF_URL_ALLOW_PLAINTEXT:-0}" == "1" ]]; then
                            echo -e "\033[0;33m[WARN]\033[0m Clipboard unavailable. Manual copy:"
                            echo "  ${url}"
                        else
                            echo -e "\033[0;33m[WARN]\033[0m Browser and clipboard unavailable."
                            echo "  Re-run with FREEBUFF_URL_ALLOW_PLAINTEXT=1 to print the URL."
                        fi
                    }
                }
            elif [[ -n "${url}" ]]; then
                echo -e "\033[0;33m[WARN]\033[0m Rejected an invalid login URL."
            fi
        fi
        sleep 0.5
    done
    rm -f "${URL_BRIDGE_FILE}" "${SESSION_DIR}"/login-url.claimed.* 2>/dev/null || true
}

url_watcher &
WATCHER_PID=$!
FREEBUFF_PID=""
FREEBUFF_PGID=""
TERMINATION_SIGNAL=""
TERMINATION_EXIT_CODE=""
PGID_FILE="${SESSION_DIR}/proot-pgid"

freebuff_group_alive() {
    if [[ "${FREEBUFF_PGID}" =~ ^[0-9]+$ ]]; then
        kill -0 -- "-${FREEBUFF_PGID}" 2>/dev/null
    elif [[ -n "${FREEBUFF_PID}" ]]; then
        kill -0 "${FREEBUFF_PID}" 2>/dev/null
    else
        return 1
    fi
}

signal_freebuff_group() {
    local signal="$1"
    if [[ "${FREEBUFF_PGID}" =~ ^[0-9]+$ ]] && kill -0 -- "-${FREEBUFF_PGID}" 2>/dev/null; then
        kill -s "${signal}" -- "-${FREEBUFF_PGID}" 2>/dev/null || true
    elif [[ -n "${FREEBUFF_PID}" ]] && kill -0 "${FREEBUFF_PID}" 2>/dev/null; then
        kill -s "${signal}" "${FREEBUFF_PID}" 2>/dev/null || true
    fi
}

wait_for_freebuff_exit() {
    local deadline=$((SECONDS + KILL_GRACE_SECONDS))
    while freebuff_group_alive; do
        [[ ${SECONDS} -ge ${deadline} ]] && return 1
        sleep 0.1
    done
}

stop_freebuff_group() {
    local initial_signal="${1:-TERM}"
    signal_freebuff_group "${initial_signal}"
    wait_for_freebuff_exit && return 0
    if [[ "${initial_signal}" != "TERM" ]]; then
        signal_freebuff_group 'TERM'
        wait_for_freebuff_exit && return 0
    fi
    signal_freebuff_group 'KILL'
    wait_for_freebuff_exit || true
}

forward_signal() {
    local signal="$1"
    TERMINATION_SIGNAL="${signal}"
    case "${signal}" in
        INT) TERMINATION_EXIT_CODE=130 ;;
        TERM) TERMINATION_EXIT_CODE=143 ;;
    esac
    signal_freebuff_group "${signal}"
}

cleanup() {
    local exit_code=$?
    trap - EXIT

    if freebuff_group_alive; then
        stop_freebuff_group 'TERM'
    fi
    if [[ -n "${FREEBUFF_PID}" ]]; then
        wait "${FREEBUFF_PID}" 2>/dev/null || true
    fi

    if kill -0 "${WATCHER_PID}" 2>/dev/null; then
        kill -s TERM "${WATCHER_PID}" 2>/dev/null || true
    fi
    wait "${WATCHER_PID}" 2>/dev/null || true
    rm -f "${URL_BRIDGE_FILE}" "${PGID_FILE}" "${SESSION_DIR}"/login-url.claimed.* 2>/dev/null || true
    rmdir "${SESSION_DIR}" 2>/dev/null || true
    rmdir "${BRIDGE_ROOT}" 2>/dev/null || true
    exit "${exit_code}"
}
trap cleanup EXIT
trap 'forward_signal INT' INT
trap 'forward_signal TERM' TERM

# ─── FreeBuff 실행 ───────────────────────────────────────────
# --norc --noprofile: proot-distro v5.x에서 bash -c 실행 시 프로파일이
# PATH를 덮어쓰는 문제를 막고 전용 pinned runtime을 시스템 명령보다 우선한다.
setsid --wait "${BASH}" --norc --noprofile -c \
    'set -e; pgid_file="$1"; shift; printf "%s\n" "$$" >"${pgid_file}.tmp"; chmod 600 "${pgid_file}.tmp"; mv -f "${pgid_file}.tmp" "${pgid_file}"; exec "$@"' \
    -- "${PGID_FILE}" "${PROOT_LOGIN[@]}" "${DISTRO}" -- /bin/bash --norc --noprofile -c \
    'export PATH=/opt/freebuff-termux/current-freebuff/bin:/opt/freebuff-termux/current-node/bin:/usr/local/bin:/usr/bin:/bin:$PATH; export OVERRIDE_PLATFORM=linux; export FREEBUFF_URL_BRIDGE_FILE="$1"; export FREEBUFF_URL_ALLOW_PLAINTEXT="$2"; cd -- "$3" || exit; shift 3; exec /opt/freebuff-termux/current-freebuff/bin/freebuff "$@"' \
    -- "${GUEST_URL_BRIDGE_FILE}" "${FREEBUFF_URL_ALLOW_PLAINTEXT:-0}" "${PROOT_CWD}" "$@" <&0 &
FREEBUFF_PID=$!

for ((attempt = 0; attempt < 50; attempt += 1)); do
    if [[ -f "${PGID_FILE}" ]]; then
        IFS= read -r FREEBUFF_PGID <"${PGID_FILE}" || true
        break
    fi
    kill -0 "${FREEBUFF_PID}" 2>/dev/null || break
    sleep 0.1
done
if [[ -n "${FREEBUFF_PGID}" ]] && [[ ! "${FREEBUFF_PGID}" =~ ^[0-9]+$ ]]; then
    echo "freebuff: invalid process-group state" >&2
    exit 2
fi
if [[ -z "${FREEBUFF_PGID}" ]] && kill -0 "${FREEBUFF_PID}" 2>/dev/null; then
    echo "freebuff: process-group initialization timed out" >&2
    exit 2
fi
if [[ -n "${TERMINATION_SIGNAL}" ]]; then
    # A signal can arrive after the PGID file is published but before the
    # main wait starts. Escalate here as well; otherwise an early TERM sent to
    # a child that ignores it leaves the wrapper blocked in wait forever.
    stop_freebuff_group "${TERMINATION_SIGNAL}"
fi

set +e
wait "${FREEBUFF_PID}"
FREEBUFF_EXIT_CODE=$?
if [[ -n "${TERMINATION_SIGNAL}" ]]; then
    if freebuff_group_alive; then
        stop_freebuff_group "${TERMINATION_SIGNAL}"
    fi
    wait "${FREEBUFF_PID}" 2>/dev/null || true
    FREEBUFF_EXIT_CODE="${TERMINATION_EXIT_CODE}"
fi
set -e
FREEBUFF_PID=""
exit "${FREEBUFF_EXIT_CODE}"
