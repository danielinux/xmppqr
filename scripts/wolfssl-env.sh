#!/usr/bin/env bash

wolfssl_env_get() {
    local key="$1"
    local file="$2"
    local line name value

    [[ -f "$file" ]] || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
        [[ "$line" == *=* ]] || continue

        name="${line%%=*}"
        value="${line#*=}"
        name="${name%"${name##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"

        if [[ "$name" == "$key" ]]; then
            if [[ "${value:0:1}" == "\"" && "${value: -1}" == "\"" ]] ||
               [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
                value="${value:1:${#value}-2}"
            fi
            printf '%s\n' "$value"
            return 0
        fi
    done < "$file"

    return 1
}

wolfssl_sanitize_ref() {
    local ref="$1"
    ref="${ref#refs/tags/}"
    printf '%s\n' "$ref" | sed 's/[^A-Za-z0-9._-]/_/g'
}

wolfssl_archive_ref() {
    local ref="$1"
    ref="${ref#refs/tags/}"
    printf '%s\n' "$ref"
}

wolfssl_resolve_env() {
    local root="$1"
    local ref_arg="${2:-}"
    local env_file="$root/.env"
    local env_ref=""
    local env_prefix=""

    if [[ -z "${XMPPQR_WOLFSSL_REF:-}" ]]; then
        env_ref="$(wolfssl_env_get XMPPQR_WOLFSSL_REF "$env_file" || true)"
    fi
    if [[ -z "${XMPPQR_WOLFSSL_PREFIX:-}" ]]; then
        env_prefix="$(wolfssl_env_get XMPPQR_WOLFSSL_PREFIX "$env_file" || true)"
    fi

    WOLFSSL_REF="${ref_arg:-${XMPPQR_WOLFSSL_REF:-${env_ref:-v5.9.1-stable}}}"
    WOLFSSL_REF_SLUG="$(wolfssl_sanitize_ref "$WOLFSSL_REF")"
    WOLFSSL_ARCHIVE_REF="$(wolfssl_archive_ref "$WOLFSSL_REF")"
    WOLFSSL_PREFIX="${XMPPQR_WOLFSSL_PREFIX:-${env_prefix:-$root/.local/wolfssl-$WOLFSSL_REF_SLUG}}"
    WOLFSSL_SRC_DIR="$root/.local/src/wolfssl-$WOLFSSL_REF_SLUG"
    WOLFSSL_ARCHIVE="$root/.local/src/wolfssl-$WOLFSSL_REF_SLUG.tar.gz"

    if [[ "$WOLFSSL_PREFIX" != /* ]]; then
        WOLFSSL_PREFIX="$root/$WOLFSSL_PREFIX"
    fi

    export WOLFSSL_REF
    export WOLFSSL_REF_SLUG
    export WOLFSSL_ARCHIVE_REF
    export WOLFSSL_PREFIX
    export WOLFSSL_SRC_DIR
    export WOLFSSL_ARCHIVE
}
