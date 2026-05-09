#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1')}"

. "$ROOT/scripts/wolfssl-env.sh"
wolfssl_resolve_env "$ROOT" "${1:-}"

if [[ ! -d "$WOLFSSL_SRC_DIR" ]]; then
    mkdir -p "$(dirname "$WOLFSSL_ARCHIVE")"
    if [[ ! -f "$WOLFSSL_ARCHIVE" ]]; then
        curl -fsSL \
            "https://github.com/wolfSSL/wolfssl/archive/refs/tags/$WOLFSSL_ARCHIVE_REF.tar.gz" \
            -o "$WOLFSSL_ARCHIVE"
    fi
    tmpdir="$(mktemp -d "$ROOT/.local/src/wolfssl-extract.XXXXXX")"
    trap 'rm -rf "$tmpdir"' EXIT
    tar -xzf "$WOLFSSL_ARCHIVE" -C "$tmpdir"
    extracted="$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    if [[ -z "$extracted" ]]; then
        printf 'failed to extract wolfSSL archive: %s\n' "$WOLFSSL_ARCHIVE" >&2
        exit 1
    fi
    mv "$extracted" "$WOLFSSL_SRC_DIR"
    rm -rf "$tmpdir"
    trap - EXIT
fi

if [[ ! -x "$WOLFSSL_SRC_DIR/configure" ]]; then
    (cd "$WOLFSSL_SRC_DIR" && ./autogen.sh)
fi

mkdir -p "$WOLFSSL_PREFIX"

configure_args=(
    "--prefix=$WOLFSSL_PREFIX"
    "--disable-shared"
    "--enable-static"
    "--disable-examples"
    "--disable-crypttests"
    "--enable-opensslextra"
    "--enable-tlsx"
    "--enable-sni"
    "--enable-sessioncerts"
    "--enable-blake2"
    "--enable-hkdf"
    "--enable-aesgcm"
    "--enable-curve25519"
    "--enable-ed25519"
    "--enable-pwdbased"
    "--enable-scrypt"
    "--enable-keying-material"
    "--enable-kyber"
    "--enable-dilithium"
    "--enable-experimental"
)

(
    cd "$WOLFSSL_SRC_DIR"
    CFLAGS="${CFLAGS:-"-O2 -fPIC"}" ./configure "${configure_args[@]}"
    make -j"$JOBS"
    make install
)

lib="$WOLFSSL_PREFIX/lib/libwolfssl.a"
pc="$WOLFSSL_PREFIX/lib/pkgconfig/wolfssl.pc"
if [[ ! -f "$lib" ]]; then
    printf 'missing expected static library: %s\n' "$lib" >&2
    exit 1
fi
if [[ ! -f "$pc" ]]; then
    printf 'missing expected pkg-config file: %s\n' "$pc" >&2
    exit 1
fi

required_symbols=(
    wc_InitBlake2b
    wc_scrypt
    wc_dilithium_make_key
    wc_MlKemKey_New
    wolfSSL_export_keying_material
    wolfSSL_get_peer_chain
    wolfSSL_get_servername
    wolfSSL_CTX_set_min_proto_version
)

for symbol in "${required_symbols[@]}"; do
    if ! nm -g "$lib" | awk -v symbol="$symbol" '$NF == symbol { found = 1 } END { exit found ? 0 : 1 }'; then
        printf 'local wolfSSL is missing required symbol: %s\n' "$symbol" >&2
        exit 1
    fi
done

printf 'local wolfSSL ready: %s (%s)\n' "$WOLFSSL_PREFIX" "$WOLFSSL_REF"
