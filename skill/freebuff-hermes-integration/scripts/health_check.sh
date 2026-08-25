#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
# FreeBuff Termux Health Check
# ============================================================================
# FreeBuff 실행 전 환경이 올바르게 구성되었는지 검사한다.
# ============================================================================

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
DISTRO_FILE="${XDG_CONFIG_HOME:-${HOME}/.config}/freebuff-termux/distro"
DISTRO="${FREEBUFF_PROOT_DISTRO:-}"
if [[ -z "${DISTRO}" ]] && [[ -f "${DISTRO_FILE}" ]] && [[ ! -L "${DISTRO_FILE}" ]]; then
    IFS= read -r DISTRO <"${DISTRO_FILE}" || true
fi
DISTRO="${DISTRO:-ubuntu}"
if [[ ! "${DISTRO}" =~ ^[[:alnum:]][[:alnum:]._-]{0,63}$ ]] || [[ "${DISTRO}" == "." ]] || [[ "${DISTRO}" == ".." ]]; then
    echo "Invalid configured distro identifier." >&2
    exit 2
fi

check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo -e "  ${GREEN}[PASS]${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}[FAIL]${NC} $desc"
        FAIL=$((FAIL + 1))
    fi
}

is_termux_environment() {
    [[ -n "${PREFIX:-}" ]] && [[ "${PREFIX}" == /data/data/com.termux* ]]
}

is_distro_installed() {
    proot-distro list --quiet 2>/dev/null | grep -Fxq -- "${DISTRO}"
}

echo "FreeBuff Termux Health Check"
echo "================================"
echo ""

echo "1. Termux Environment"
check "Running in Termux" is_termux_environment
check "git installed" command -v git
echo ""

echo "2. proot-distro"
check "proot-distro installed" command -v proot-distro
check "setsid available" command -v setsid
check "Configured distro installed (${DISTRO})" is_distro_installed
echo ""

echo "3. Node.js & FreeBuff (inside proot)"
PROOT_LOGIN=(proot-distro login --user root --isolated --shared-home "${DISTRO}")
PINNED_RUNTIME_PATH='/opt/freebuff-termux/current-freebuff/bin:/opt/freebuff-termux/current-node/bin:/usr/local/bin:/usr/bin:/bin'
check "Node.js installed in distro" \
    "${PROOT_LOGIN[@]}" -- /bin/bash --norc --noprofile -c \
    'export PATH="$1:$PATH"; command -v node' -- "${PINNED_RUNTIME_PATH}"
check "FreeBuff installed in distro" \
    "${PROOT_LOGIN[@]}" -- /bin/bash --norc --noprofile -c \
    'test -x /opt/freebuff-termux/current-freebuff/bin/freebuff'
echo ""

echo "4. Storage & Memory"
if [[ "${FREEBUFF_STORAGE_BIND:-0}" == "1" ]]; then
    check "Storage setup (~/storage)" test -d "${HOME}/storage"
    check "Shared storage accessible" test -d "/storage/emulated/0"
else
    echo -e "  ${YELLOW}[INFO]${NC} Shared storage bind is disabled by default"
fi

MEMINFO=$(cat /proc/meminfo 2>/dev/null || echo "")
if [[ -n "$MEMINFO" ]]; then
    MEM_AVAILABLE=$(echo "$MEMINFO" | grep MemAvailable | awk '{print $2}')
    MEM_MB=$((MEM_AVAILABLE / 1024))
    if [[ $MEM_MB -gt 512 ]]; then
        echo -e "  ${GREEN}[PASS]${NC} Memory: ${MEM_MB}MB available (>=512MB)"
        PASS=$((PASS + 1))
    elif [[ $MEM_MB -gt 128 ]]; then
        echo -e "  ${YELLOW}[WARN]${NC} Memory: ${MEM_MB}MB available (caution, <512MB)"
    else
        echo -e "  ${RED}[FAIL]${NC} Memory: ${MEM_MB}MB available (danger, <128MB)"
        FAIL=$((FAIL + 1))
    fi
else
    echo -e "  ${YELLOW}[WARN]${NC} Memory: unavailable (unknown)"
fi
echo ""

echo "5. Wake Lock"
check "termux-wake-lock available" command -v termux-wake-lock
echo ""

echo "================================"
echo -e "Passed: ${GREEN}${PASS}${NC}  Failed: ${RED}${FAIL}${NC}"
if [[ $FAIL -gt 0 ]]; then
    echo -e "${RED}Some checks failed. Run: bash scripts/install.sh${NC}"
    exit 1
else
    echo -e "${GREEN}All checks passed. FreeBuff is ready to run.${NC}"
    exit 0
fi
