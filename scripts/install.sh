#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
# FreeBuff Termux Installation Script
# B+C 하이브리드 전략: proot-distro + 경로 브리지
# ============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

DISTRO="${1:-ubuntu}"
WRAPPER_DIR="${HOME}/.local/bin"
WRAPPER_PATH="${WRAPPER_DIR}/freebuff"
PROOT_LOGIN="proot-distro login --user root --bind /storage/emulated/0"

# ─── 1. Termux 환경 확인 ────────────────────────────────────
log_info "Checking Termux environment..."
if [[ -z "${PREFIX:-}" ]] || [[ ! "${PREFIX}" == /data/data/com.termux* ]]; then
    log_error "This script must be run inside Termux."
    exit 1
fi
log_ok "Running in Termux (PREFIX: ${PREFIX})"

# ─── 2. Termux 패키지 의존성 설치 ────────────────────────────
log_info "Preparing Termux packages..."
dpkg --configure -a 2>/dev/null || true
pkg upgrade -y 2>/dev/null || true
pkg update -y
pkg install -y proot-distro nodejs git curl
if ! command -v proot-distro &>/dev/null; then
    log_error "Failed to install proot-distro."
    exit 1
fi
log_ok "Termux dependencies installed"

# ─── 3. proot-distro distro 설치 ─────────────────────────────
log_info "Installing ${DISTRO} distro via proot-distro..."
if proot-distro list --installed 2>/dev/null | grep -qw "${DISTRO}"; then
    log_ok "Distro '${DISTRO}' is already installed"
else
    if proot-distro install "${DISTRO}" 2>&1 | tee /dev/stderr | grep -q "already exists"; then
        log_ok "Distro '${DISTRO}' already exists (container present)"
    elif [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        if proot-distro list --installed 2>/dev/null | grep -qw "${DISTRO}"; then
            log_ok "Distro '${DISTRO}' confirmed installed"
        else
            log_error "Failed to install ${DISTRO} distro"
            exit 1
        fi
    else
        log_ok "Distro '${DISTRO}' installed successfully"
    fi
fi

# ─── 4. distro 내부에 Bun 설치 ───────────────────────────────
log_info "Installing Bun runtime inside ${DISTRO}..."
BUN_CHECK=$(${PROOT_LOGIN} "${DISTRO}" -- bash -lc 'command -v bun' 2>/dev/null || true)
if [[ -n "${BUN_CHECK}" ]]; then
    log_ok "Bun is already installed in ${DISTRO}"
else
    ${PROOT_LOGIN} "${DISTRO}" -- bash -lc 'curl -fsSL https://bun.sh/install | bash'
    log_ok "Bun installed in ${DISTRO}"
fi

# ─── 5. distro 내부에 FreeBuff 설치 ──────────────────────────
log_info "Installing FreeBuff CLI inside ${DISTRO}..."
FB_CMD='export BUN_INSTALL="$HOME/.bun" && export PATH="$BUN_INSTALL/bin:$PATH"'
FREEBUFF_CHECK=$(${PROOT_LOGIN} "${DISTRO}" -- bash -lc "${FB_CMD} && command -v freebuff" 2>/dev/null || true)
if [[ -n "${FREEBUFF_CHECK}" ]]; then
    log_ok "FreeBuff is already installed in ${DISTRO}"
else
    ${PROOT_LOGIN} "${DISTRO}" -- bash -lc "${FB_CMD} && bun install -g freebuff"
    log_ok "FreeBuff installed in ${DISTRO}"
fi

# ─── 6. 래퍼 스크립트 생성 ───────────────────────────────────
log_info "Creating FreeBuff wrapper script..."
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

# ─── 7. PATH 등록 ────────────────────────────────────────────
log_info "Registering wrapper in PATH..."
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
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN} FreeBuff Termux installation complete!  ${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\nDistro:  ${BLUE}${DISTRO}${NC}"
echo -e "Wrapper: ${BLUE}${WRAPPER_PATH}${NC}\n"
if [[ -n "${SHELL_RC}" ]]; then
    echo -e "${YELLOW}Run: source ${SHELL_RC}${NC}\n"
fi
echo -e "Usage: ${BLUE}cd ~/my-project && freebuff${NC}\n"

