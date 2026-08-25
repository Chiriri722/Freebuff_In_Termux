#!/usr/bin/env bash
# Durable managed-file transaction helpers. Targets are supplied by trusted
# installer code and are deliberately never read from transaction metadata.

install_transaction_validate_context() {
    local context="$1"
    [[ "${context}" =~ ^[[:alnum:]][[:alnum:]._-]{0,63}$ ]] \
        && [[ "${context}" != "." ]] && [[ "${context}" != ".." ]]
}

install_transaction_begin() {
    local transaction_dir="$1" context="$2"
    shift 2
    local parent staging stale index target status

    install_transaction_validate_context "${context}" || return 2
    if [[ -e "${transaction_dir}" ]] || [[ -L "${transaction_dir}" ]]; then
        return 2
    fi

    for stale in "${transaction_dir}.tmp."*; do
        if [[ ! -e "${stale}" ]] && [[ ! -L "${stale}" ]]; then
            continue
        fi
        if [[ ! -d "${stale}" ]] || [[ -L "${stale}" ]]; then
            return 2
        fi
        rm -rf -- "${stale}" || return 1
    done

    parent="$(dirname -- "${transaction_dir}")"
    mkdir -p -- "${parent}" || return 1
    chmod 700 "${parent}" || return 1
    staging="$(mktemp -d "${transaction_dir}.tmp.XXXXXX")" || return 1
    chmod 700 "${staging}" || {
        rm -rf -- "${staging}"
        return 1
    }

    {
        printf 'schema=1\n'
        printf 'context=%s\n' "${context}"
        printf 'count=%s\n' "$#"
    } >"${staging}/metadata" || {
        rm -rf -- "${staging}"
        return 1
    }

    index=0
    for target in "$@"; do
        status='absent'
        if [[ -e "${target}" ]] || [[ -L "${target}" ]]; then
            cp -a -- "${target}" "${staging}/backup.${index}" || {
                rm -rf -- "${staging}"
                return 1
            }
            status='present'
        fi
        printf '%s\n' "${status}" >"${staging}/status.${index}" || {
            rm -rf -- "${staging}"
            return 1
        }
        index=$((index + 1))
    done

    mv -- "${staging}" "${transaction_dir}" || {
        rm -rf -- "${staging}"
        return 1
    }
}

install_transaction_recover() {
    local transaction_dir="$1" context="$2"
    shift 2
    local schema recorded_context recorded_count index status target
    local -a targets=("$@")

    install_transaction_validate_context "${context}" || return 2
    if [[ ! -d "${transaction_dir}" ]] || [[ -L "${transaction_dir}" ]]; then
        return 2
    fi
    if [[ ! -f "${transaction_dir}/metadata" ]] || [[ -L "${transaction_dir}/metadata" ]]; then
        return 2
    fi
    schema="$(awk -F= '$1 == "schema" { print $2; exit }' "${transaction_dir}/metadata")"
    recorded_context="$(awk -F= '$1 == "context" { print $2; exit }' "${transaction_dir}/metadata")"
    recorded_count="$(awk -F= '$1 == "count" { print $2; exit }' "${transaction_dir}/metadata")"
    if [[ "${schema}" != "1" ]] || [[ "${recorded_context}" != "${context}" ]] \
        || [[ ! "${recorded_count}" =~ ^[0-9]+$ ]] || [[ "${recorded_count}" -ne "$#" ]]; then
        return 2
    fi

    for ((index = 0; index < recorded_count; index += 1)); do
        if [[ ! -f "${transaction_dir}/status.${index}" ]] \
            || [[ -L "${transaction_dir}/status.${index}" ]]; then
            return 2
        fi
        IFS= read -r status <"${transaction_dir}/status.${index}" || return 2
        case "${status}" in
            present)
                if [[ ! -e "${transaction_dir}/backup.${index}" ]] \
                    && [[ ! -L "${transaction_dir}/backup.${index}" ]]; then
                    return 2
                fi
                ;;
            absent) ;;
            *) return 2 ;;
        esac
    done

    for ((index = recorded_count - 1; index >= 0; index -= 1)); do
        target="${targets[index]}"
        IFS= read -r status <"${transaction_dir}/status.${index}" || return 2
        if [[ -d "${target}" ]] && [[ ! -L "${target}" ]]; then
            return 2
        fi
        rm -f -- "${target}" || return 1
        if [[ "${status}" == 'present' ]]; then
            mkdir -p -- "$(dirname -- "${target}")" || return 1
            cp -a -- "${transaction_dir}/backup.${index}" "${target}" || return 1
        fi
    done

    rm -rf -- "${transaction_dir}"
}

install_transaction_commit() {
    local transaction_dir="$1"
    if [[ ! -d "${transaction_dir}" ]] || [[ -L "${transaction_dir}" ]]; then
        return 2
    fi
    rm -rf -- "${transaction_dir}"
}
