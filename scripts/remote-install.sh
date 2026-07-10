#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
# FreeBuff Termux — Remote One-Line Installer
# ============================================================================
# 사용법:
#   curl -fsSL https://raw.githubusercontent.com/Chiriri722/Freebuff_In_Termux/main/scripts/remote-install.sh | bash
#
# 또는 distro 지정:
#   curl -fsSL https://raw.githubusercontent.com/Chiriri722/Freebuff_In_Termux/main/scripts/remote-install.sh | bash -s -- debian
#
# 이 스크립트는 다음을 자동 수행한다:
#   1. Termux 환경 확인
#   2. Termux 패키지 의존성 설치 (proot-distro, nodejs, git, curl)
#   3. GitHub에서 저장소 클론
#   4. npm 의존성 설치 + TypeScript 빌드
#   5. proot-distro에 Ubuntu (또는 지정 distro) 설치
#   6. distro 내부에 Bun 런타임 설치
#   7. distro 내부에 FreeBuff CLI 설치
#   8. 래퍼 스크립트 생성 (~/.local/bin/freebuff)
#   9. PATH 등록
# ============================================================================
set -euo pipefail

# ─── 색상 ────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ─── 설정 ────────────────────────────────────────────────────
DISTRO="${1:-ubuntu}"
REPO_URL="https://github.com/Chiriri722/Freebuff_In_Termux.git"
INSTALL_DIR="${HOME}/.freebuff-termux"
WRAPPER_DIR="${HOME}/.local/bin"
WRAPPER_PATH="${WRAPPER_DIR}/freebuff"
PROOT_LOGIN="proot-distro login --user root --bind /storage/emulated/0"

echo -e "${GREEN}"
echo "  ____             _            _           ____  _               _           "
echo " |  _ \\  __ _  ___| | _____  __| |_   _    / ___|| |__   ___  ___| |_ ___ _ __ "
echo " | | | |/ _\` |/ __| |/ / _ \\/ _\` | | | |   \\___ \\| '_ \\ / _ \\/ __| __/ _ \\ '__|"
echo " | |_| | (_| | (__|   <  __/ (_| | |_| |    ___) | | | |  __/ (__| ||  __/ |   "
echo " |____/ \\__,_|\\___|_|\\_\\___|\\__,_|\\__, |   |____/|_| |_|\\___|\\___|\\__\\___|_|   "
echo "                                    |___/                                       "
echo -e "${NC}"
echo "  Termux Compatibility Layer — B+C Hybrid Strategy"
echo ""

# ─── 1. Termux 환경 확인 ────────────────────────────────────
log_info "Step 1/9: Checking Termux environment..."
if [[ -z "${PREFIX:-}" ]] || [[ ! "${PREFIX}" == /data/data/com.termux* ]]; then
    log_error "This script must be run inside Termux."
    log_error "Install Termux from F-Droid: https://f-droid.org/packages/com.termux/"
    exit 1
fi
log_ok "Running in Termux (PREFIX: ${PREFIX})"

# ─── 2. Termux 패키지 의존성 설치 ────────────────────────────
log_info "Step 2/9: Preparing Termux packages..."

# 2-1. dpkg 손상 상태 복구 (이전 설치 중단 시 half-configured 잔존 해결)
log_info "  Running dpkg --configure -a (fix broken state)..."
dpkg --configure -a 2>/dev/null || true

# 2-2. 전체 패키지 업그레이드 (libc++ 등 라이브러리 버전 불일치 해결)
#      ffmpeg/libplacebo 링크 에러 등 부분 업데이트 문제를 사전 방지
log_info "  Running pkg upgrade (sync all package versions)..."
pkg upgrade -y 2>/dev/null || true

# 2-3. 패키지 목록 업데이트
log_info "  Running pkg update..."
pkg update -y

# 2-4. 의존성 설치
log_info "  Installing required packages..."
pkg install -y proot-distro nodejs git curl

if ! command -v proot-distro &>/dev/null; then
    log_error "Failed to install proot-distro."
    log_error "Try manually: dpkg --configure -a && pkg upgrade -y && pkg install proot-distro"
    exit 1
fi
if ! command -v node &>/dev/null; then
    log_error "Failed to install Node.js."
    exit 1
fi
log_ok "Termux dependencies installed (proot-distro, nodejs, git, curl)"

# ─── 3. GitHub에서 저장소 클론 ───────────────────────────────
log_info "Step 3/9: Cloning FreeBuff Termux repository..."
if [[ -d "${INSTALL_DIR}/.git" ]]; then
    log_info "Repository exists, pulling latest..."
    cd "${INSTALL_DIR}"
    git pull --ff-only
else
    git clone "${REPO_URL}" "${INSTALL_DIR}"
    cd "${INSTALL_DIR}"
fi
log_ok "Repository ready at ${INSTALL_DIR}"

# ─── 4. npm 의존성 설치 + 빌드 ───────────────────────────────
log_info "Step 4/9: Installing npm dependencies and building..."
npm install
npm run build
if [[ ! -f "dist/index.js" ]]; then
    log_error "Build failed: dist/index.js not found."
    exit 1
fi
log_ok "TypeScript build complete (dist/index.js)"

# ─── 5. proot-distro distro 설치 ─────────────────────────────
log_info "Step 5/9: Installing ${DISTRO} distro via proot-distro..."
if proot-distro list --installed 2>/dev/null | grep -q "^${DISTRO}$"; then
    log_ok "Distro '${DISTRO}' is already installed"
else
    proot-distro install "${DISTRO}"
    log_ok "Distro '${DISTRO}' installed successfully"
fi

# ─── 6. distro 내부에 Bun 설치 ───────────────────────────────
log_info "Step 6/9: Installing Bun runtime inside ${DISTRO}..."
BUN_CHECK=$(${PROOT_LOGIN} "${DISTRO}" -- bash -lc 'command -v bun' 2>/dev/null || true)
if [[ -n "${BUN_CHECK}" ]]; then
    log_ok "Bun is already installed in ${DISTRO}"
else
    ${PROOT_LOGIN} "${DISTRO}" -- bash -lc 'curl -fsSL https://bun.sh/install | bash'
    log_ok "Bun installed in ${DISTRO}"
fi

# ─── 7. distro 내부에 FreeBuff 설치 ──────────────────────────
log_info "Step 7/9: Installing FreeBuff CLI inside ${DISTRO}..."
FB_CMD='export BUN_INSTALL="$HOME/.bun" && export PATH="$BUN_INSTALL/bin:$PATH"'
FREEBUFF_CHECK=$(${PROOT_LOGIN} "${DISTRO}" -- bash -lc "${FB_CMD} && command -v freebuff" 2>/dev/null || true)
if [[ -n "${FREEBUFF_CHECK}" ]]; then
    log_ok "FreeBuff is already installed in ${DISTRO}"
else
    ${PROOT_LOGIN} "${DISTRO}" -- bash -lc "${FB_CMD} && bun install -g freebuff"
    log_ok "FreeBuff installed in ${DISTRO}"
fi

# ─── 8. 래퍼 스크립트 생성 ───────────────────────────────────
log_info "Step 8/9: Creating FreeBuff wrapper script..."
mkdir -p "${WRAPPER_DIR}"
WRAPPER_EOF=$(cat << 'WRAPPER_INNER'
#!/data/data/com.termux/files/usr/bin/bash
# FreeBuff Termux Wrapper — proot-distro 환경에서 freebuff 실행
#
# 핵심: proot 내부에서도 process.platform이 'android'로 보고되어
# freebuff 런처가 바이너리 다운로드를 거부하는 문제를 해결하기 위해
# OVERRIDE_PLATFORM=linux 환경 변수를 주입한다.
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
exec ${PROOT_LOGIN} "${DISTRO}" -- bash -lc \
    "export BUN_INSTALL=\"\$HOME/.bun\" && export PATH=\"\$BUN_INSTALL/bin:\$PATH\" && export OVERRIDE_PLATFORM=linux && cd '${PROOT_CWD}' && freebuff \"\$@\"" \
    -- "$@"
WRAPPER_INNER
)
echo "${WRAPPER_EOF}" > "${WRAPPER_PATH}"
chmod +x "${WRAPPER_PATH}"
log_ok "Wrapper script created at ${WRAPPER_PATH}"

# ─── 9. PATH 등록 ────────────────────────────────────────────
log_info "Step 9/9: Registering wrapper in PATH..."
SHELL_RC=""
if [[ -f "${HOME}/.bashrc" ]]; then SHELL_RC="${HOME}/.bashrc"
elif [[ -f "${HOME}/.zshrc" ]]; then SHELL_RC="${HOME}/.zshrc"; fi
if [[ -n "${SHELL_RC}" ]]; then
    if grep -q "${WRAPPER_DIR}" "${SHELL_RC}" 2>/dev/null; then
        log_ok "PATH already registered"
    else
        echo -e "\n# FreeBuff Termux wrapper PATH" >> "${SHELL_RC}"
        echo "export PATH=\"${WRAPPER_DIR}:\$PATH\"" >> "${SHELL_RC}"
        log_ok "PATH registered in ${SHELL_RC}"
    fi
else
    log_warn "Add manually: export PATH=\"${WRAPPER_DIR}:\$PATH\""
fi

# ─── 완료 ─────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} FreeBuff Termux installation complete!  ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "  Distro:     ${BLUE}${DISTRO}${NC}"
echo -e "  Repository: ${BLUE}${INSTALL_DIR}${NC}"
echo -e "  Wrapper:    ${BLUE}${WRAPPER_PATH}${NC}"
echo ""
if [[ -n "${SHELL_RC}" ]]; then
    echo -e "${YELLOW}  Restart your shell or run:${NC}"
    echo -e "    ${BLUE}source ${SHELL_RC}${NC}"
    echo ""
fi
echo -e "  Usage: ${BLUE}cd ~/my-project && freebuff${NC}"
echo ""
echo -e "  Health check: ${BLUE}bash ${INSTALL_DIR}/skill/freebuff-hermes-integration/scripts/health_check.sh${NC}"
echo ""

