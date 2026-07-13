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
DISTRO_ROOTFS="${PREFIX}/var/lib/proot-distro/containers/${DISTRO}/rootfs"

if [[ -d "${DISTRO_ROOTFS}" ]]; then
    log_ok "Distro '${DISTRO}' is already installed"
else
    proot-distro install "${DISTRO}" 2>&1 || true
    if [[ -d "${DISTRO_ROOTFS}" ]]; then
        log_ok "Distro '${DISTRO}' installed successfully"
    else
        log_error "Failed to install ${DISTRO} distro"
        log_error "Try manually: proot-distro install ${DISTRO}"
        exit 1
    fi
fi

# ─── 4. distro 내부에 Bun 설치 ───────────────────────────────
log_info "Installing Bun runtime inside ${DISTRO}..."
BUN_CHECK=$(${PROOT_LOGIN} "${DISTRO}" -- /bin/bash --norc --noprofile -c 'export PATH=/root/.bun/bin:/usr/local/bin:/usr/bin:/bin:$PATH && command -v bun' 2>/dev/null || true)
if [[ -n "${BUN_CHECK}" ]]; then
    log_ok "Bun is already installed in ${DISTRO}"
else
    ${PROOT_LOGIN} "${DISTRO}" -- /bin/bash --norc --noprofile -c 'export PATH=/root/.bun/bin:/usr/local/bin:/usr/bin:/bin:$PATH && curl -fsSL https://bun.sh/install | bash'
    log_ok "Bun installed in ${DISTRO}"
fi

# ─── 5. distro 내부에 Node.js 설치 ───────────────────────────
log_info "Installing Node.js for freebuff launcher..."
NODE_VERSION="v22.17.1"
NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-arm64.tar.gz"
NODE_TARBALL="${HOME}/node.tar.gz"

if ${PROOT_LOGIN} "${DISTRO}" -- /bin/bash --norc --noprofile -c '/usr/local/bin/node --version' 2>/dev/null; then
    log_ok "Node.js is already installed in ${DISTRO}"
else
    curl -fsSL "${NODE_URL}" -o "${NODE_TARBALL}"
    cp "${NODE_TARBALL}" "${DISTRO_ROOTFS}/tmp/node.tar.gz"
    rm "${NODE_TARBALL}"
    ${PROOT_LOGIN} "${DISTRO}" -- /bin/bash --norc --noprofile -c \
        'tar -xzf /tmp/node.tar.gz -C /usr/local --strip-components=1 && rm /tmp/node.tar.gz'
    log_ok "Node.js ${NODE_VERSION} installed in ${DISTRO}"
fi

# ─── 6. distro 내부에 FreeBuff 설치 ──────────────────────────
log_info "Installing FreeBuff CLI inside ${DISTRO}..."
FB_PATH='/usr/local/bin:/usr/bin:/bin:/root/.bun/bin'
FB_CHECK=$(${PROOT_LOGIN} "${DISTRO}" -- /bin/bash --norc --noprofile -c "export PATH=${FB_PATH}:\$PATH && command -v freebuff" 2>/dev/null || true)
if [[ -n "${FB_CHECK}" ]]; then
    log_ok "FreeBuff is already installed in ${DISTRO}"
else
    ${PROOT_LOGIN} "${DISTRO}" -- /bin/bash --norc --noprofile -c "export PATH=${FB_PATH}:\$PATH && bun install -g freebuff"
    log_ok "FreeBuff installed in ${DISTRO}"
fi

# ─── 7. xdg-open 브리지 + 래퍼 스크립트 생성 ─────────────────
log_info "Creating xdg-open bridge and FreeBuff wrapper..."
mkdir -p "${WRAPPER_DIR}"

# 7-1. xdg-open 브리지 스크립트를 proot rootfs에 설치
cat > "${DISTRO_ROOTFS}/usr/local/bin/xdg-open" << 'XDG_EOF'
#!/bin/bash
# xdg-open bridge — proot 내부에서 Termux 브라우저로 URL 전달
TERMUX_HOME="/data/data/com.termux/files/home"
URL_FILE="${TERMUX_HOME}/.freebuff-url-to-open"
if [[ $# -lt 1 ]]; then exit 1; fi
URL="$1"
echo "${URL}" > "${URL_FILE}" 2>/dev/null || {
    echo "  🔑 LOGIN URL (manual copy): ${URL}"
    exit 0
}
echo "  🔑 LOGIN URL (auto-opening browser...): ${URL}"
exit 0
XDG_EOF
chmod +x "${DISTRO_ROOTFS}/usr/local/bin/xdg-open"
log_ok "xdg-open bridge installed in proot"

# 7-2. FreeBuff 래퍼 스크립트 생성 (백그라운드 URL 감시자 포함)
cat > "${WRAPPER_PATH}" << 'WRAPPER_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# FreeBuff Termux Wrapper — proot-distro 환경에서 freebuff 실행
# - OVERRIDE_PLATFORM=linux: linux-arm64 바이너리 다운로드
# - xdg-open 브리지: 로그인 URL을 Termux 브라우저로 전달
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

# URL 브리지 파일
URL_BRIDGE_FILE="${TERMUX_HOME}/.freebuff-url-to-open"
rm -f "${URL_BRIDGE_FILE}" 2>/dev/null || true

# 백그라운드 URL 감시자
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

exec ${PROOT_LOGIN} "${DISTRO}" -- /bin/bash --norc --noprofile -c \
    "export PATH=/usr/local/bin:/usr/bin:/bin:/root/.bun/bin:\$PATH && export OVERRIDE_PLATFORM=linux && cd '${PROOT_CWD}' && freebuff \"\$@\"" \
    -- "$@"
WRAPPER_EOF
chmod +x "${WRAPPER_PATH}"
log_ok "Wrapper script created at ${WRAPPER_PATH}"

# ─── 8. PATH 등록 ────────────────────────────────────────────
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

