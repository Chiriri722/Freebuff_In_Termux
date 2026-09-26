#!/bin/bash
# ============================================================================
# xdg-open bridge — proot 내부에서 Termux 브라우저로 URL 전달
# ============================================================================
# 설치 위치: proot Ubuntu 내부 /usr/local/bin/xdg-open
# ============================================================================
set -euo pipefail
umask 077

MAX_URL_LENGTH=4096
URL_FILE="${FREEBUFF_URL_BRIDGE_FILE:-}"

is_valid_login_url() {
    local url="$1"
    [[ ${#url} -le ${MAX_URL_LENGTH} ]] || return 1
    case "${url}" in
        http://* | https://*) ;;
        *) return 1 ;;
    esac
    [[ ! "${url}" =~ [[:cntrl:]] ]]
}

print_plaintext_fallback() {
    local url="$1"
    if [[ "${FREEBUFF_URL_ALLOW_PLAINTEXT:-0}" == "1" ]]; then
        echo "  LOGIN URL: ${url}"
    else
        echo "xdg-open: URL bridge unavailable; set FREEBUFF_URL_ALLOW_PLAINTEXT=1 to print it" >&2
    fi
}

if [[ $# -lt 1 ]]; then
    echo "xdg-open: no URL provided" >&2
    exit 1
fi

URL="$1"

if ! is_valid_login_url "${URL}"; then
    echo "xdg-open: rejected invalid login URL" >&2
    exit 2
fi

if [[ -z "${URL_FILE}" ]]; then
    print_plaintext_fallback "${URL}"
    exit 3
fi

if [[ ! "${URL_FILE}" =~ ^/root/\.cache/freebuff-termux/sessions/session\.[[:alnum:]]{6}/login-url$ ]]; then
    echo "xdg-open: rejected unsafe bridge path" >&2
    print_plaintext_fallback "${URL}"
    exit 3
fi

URL_DIR="$(dirname "${URL_FILE}")"
if [[ ! -d "${URL_DIR}" ]] || [[ -L "${URL_DIR}" ]]; then
    echo "xdg-open: bridge session is unavailable" >&2
    print_plaintext_fallback "${URL}"
    exit 3
fi

TMP_FILE="$(mktemp "${URL_FILE}.tmp.XXXXXX")"
trap 'rm -f "${TMP_FILE}"' EXIT
chmod 600 "${TMP_FILE}"
printf '%s\n' "${URL}" >"${TMP_FILE}"
mv -f "${TMP_FILE}" "${URL_FILE}"
trap - EXIT

echo "xdg-open: login URL queued for the Termux bridge"

exit 0
