#!/data/data/com.termux/files/usr/bin/bash
# FreeBuff Termux Wrapper — proot-distro 환경에서 freebuff 실행
#
# 핵심 설정:
# - OVERRIDE_PLATFORM=linux: proot 내부에서도 freebuff가 linux-arm64 바이너리를 다운로드
# - PATH: /usr/local/bin(Node.js) /usr/bin:/bin(기본 유틸) /root/.bun/bin(Bun+freebuff)
# - xdg-open 브리지: FreeBuff 로그인 URL을 Termux 브라우저로 전달
#   proot-distro가 Termux 홈을 기본 노출하므로 $HOME/.freebuff-url-to-open 공유
set -euo pipefail
DISTRO="${FREEBUFF_PROOT_DISTRO:-ubuntu}"
PROOT_LOGIN="proot-distro login --user root --bind /storage/emulated/0"
TERMUX_HOME="${HOME}"
PROOT_HOME="/root"
CURRENT_DIR="$(pwd)"
if [[ "${CURRENT_DIR}" == "${TERMUX_HOME}"* ]]; then
    PROOT_CWD="${PROOT_HOME}${CURRENT_DIR#${TERMUX_HOME}}"
elif [[ "${CURRENT_DIR}" == /storage/* ]]; then
    PROOT_CWD="${CURRENT_DIR}"
else
    PROOT_CWD="${CURRENT_DIR}"
fi

# ─── URL 브리지 파일 ────────────────────────────────────────
URL_BRIDGE_FILE="${TERMUX_HOME}/.freebuff-url-to-open"
rm -f "${URL_BRIDGE_FILE}" 2>/dev/null || true

# ─── 백그라운드 URL 감시자 ───────────────────────────────────
url_watcher() {
    local count=0
    while [[ ${count} -lt 3600 ]]; do
        if [[ -f "${URL_BRIDGE_FILE}" ]]; then
            local url
            url=$(cat "${URL_BRIDGE_FILE}" 2>/dev/null || true)
            if [[ -n "${url}" ]]; then
                echo -e "\n\033[0;34m[INFO]\033[0m Opening browser for login..."
                termux-open-url "${url}" 2>/dev/null || true
                rm -f "${URL_BRIDGE_FILE}" 2>/dev/null || true
            fi
        fi
        sleep 0.5
        ((count++))
    done
    rm -f "${URL_BRIDGE_FILE}" 2>/dev/null || true
}

url_watcher &
WATCHER_PID=$!

cleanup() {
    kill "${WATCHER_PID}" 2>/dev/null || true
    rm -f "${URL_BRIDGE_FILE}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ─── FreeBuff 실행 ───────────────────────────────────────────
# --norc --noprofile: proot-distro v5.x에서 bash -c 실행 시 프로파일이
# PATH를 덮어쓰는 문제 방지 (declare -x 환경 출력 + /usr/local/bin 누락)
exec ${PROOT_LOGIN} "${DISTRO}" -- /bin/bash --norc --noprofile -c \
    "export PATH=/usr/local/bin:/usr/bin:/bin:/root/.bun/bin:\$PATH && export OVERRIDE_PLATFORM=linux && cd '${PROOT_CWD}' && freebuff \"\$@\"" \
    -- "$@"
