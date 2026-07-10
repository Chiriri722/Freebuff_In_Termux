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

check() {
    local desc="$1"
    local cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        echo -e "  ${GREEN}[PASS]${NC} $desc"
        ((PASS++))
    else
        echo -e "  ${RED}[FAIL]${NC} $desc"
        ((FAIL++))
    fi
}

echo "FreeBuff Termux Health Check"
echo "================================"
echo ""

echo "1. Termux Environment"
check "Running in Termux" '[[ -n "${PREFIX:-}" ]] && [[ "${PREFIX}" == /data/data/com.termux* ]]'
check "Node.js installed" 'command -v node'
check "npm installed" 'command -v npm'
check "git installed" 'command -v git'
echo ""

echo "2. proot-distro"
check "proot-distro installed" 'command -v proot-distro'
check "Ubuntu distro installed" 'proot-distro list --installed 2>/dev/null | grep -q "^ubuntu$"'
echo ""

echo "3. Bun & FreeBuff (inside proot)"
PROOT_LOGIN="proot-distro login --user root --bind /storage/emulated/0 ubuntu"
check "Bun installed in distro" '${PROOT_LOGIN} -- bash -lc "command -v bun" 2>/dev/null'
check "FreeBuff installed in distro" '${PROOT_LOGIN} -- bash -lc "export BUN_INSTALL=\$HOME/.bun && export PATH=\$BUN_INSTALL/bin:\$PATH && command -v freebuff" 2>/dev/null'
echo ""

echo "4. Storage & Memory"
check "Storage setup (~/.storage)" '[[ -d "${HOME}/storage" ]]'
check "Shared storage accessible" '[[ -d "/storage/emulated/0" ]]'

MEMINFO=$(cat /proc/meminfo 2>/dev/null || echo "")
if [[ -n "$MEMINFO" ]]; then
    MEM_AVAILABLE=$(echo "$MEMINFO" | grep MemAvailable | awk '{print $2}')
    MEM_MB=$((MEM_AVAILABLE / 1024))
    if [[ $MEM_MB -gt 512 ]]; then
        echo -e "  ${GREEN}[PASS]${NC} Memory: ${MEM_MB}MB available (>=512MB)"
        ((PASS++))
    elif [[ $MEM_MB -gt 128 ]]; then
        echo -e "  ${YELLOW}[WARN]${NC} Memory: ${MEM_MB}MB available (caution, <512MB)"
    else
        echo -e "  ${RED}[FAIL]${NC} Memory: ${MEM_MB}MB available (danger, <128MB)"
        ((FAIL++))
    fi
fi
echo ""

echo "5. Wake Lock"
check "termux-wake-lock available" 'command -v termux-wake-lock'
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
