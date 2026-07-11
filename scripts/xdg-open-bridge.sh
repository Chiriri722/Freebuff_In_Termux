#!/bin/bash
# ============================================================================
# xdg-open bridge — proot 내부에서 Termux 브라우저로 URL 전달
# ============================================================================
# proot 내부의 HOME은 /root (rootfs 내부)이므로 Termux 홈에 접근 불가.
# 하지만 proot-distro는 Termux 홈 디렉토리를 노출하므로
# 절대 경로로 직접 접근한다.
#
# 설치 위치: proot Ubuntu 내부 /usr/local/bin/xdg-open
# ============================================================================

# Termux 홈 절대 경로 (proot가 노출하는 실제 경로)
TERMUX_HOME="/data/data/com.termux/files/home"
URL_FILE="${TERMUX_HOME}/.freebuff-url-to-open"

if [[ $# -lt 1 ]]; then
    echo "xdg-open: no URL provided" >&2
    exit 1
fi

URL="$1"

# URL을 감시 파일에 기록
echo "${URL}" > "${URL_FILE}" 2>/dev/null || {
    echo ""
    echo "=========================================="
    echo "  🔑 LOGIN URL (manual copy required):"
    echo "  ${URL}"
    echo "=========================================="
    exit 0
}

# 터미널에도 URL 출력 (백업)
echo ""
echo "=========================================="
echo "  🔑 LOGIN URL (auto-opening browser...):"
echo "  ${URL}"
echo "=========================================="
echo ""

exit 0
