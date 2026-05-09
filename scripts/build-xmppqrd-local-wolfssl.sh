#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

. "$ROOT/scripts/wolfssl-env.sh"
wolfssl_resolve_env "$ROOT" "${1:-}"

if [[ ! -f "$WOLFSSL_PREFIX/lib/libwolfssl.a" || ! -f "$WOLFSSL_PREFIX/lib/pkgconfig/wolfssl.pc" ]]; then
    "$ROOT/scripts/build-local-wolfssl.sh" "$WOLFSSL_REF"
fi

export PKG_CONFIG_LIBDIR="$WOLFSSL_PREFIX/lib/pkgconfig"
export CGO_LDFLAGS="${CGO_LDFLAGS:+$CGO_LDFLAGS }-lm"

cd "$ROOT"
go build -a -o ./xmppqrd ./cmd/xmppqrd
go build -a -o ./xmppqrctl ./cmd/xmppqrctl
go build -a -o ./x3dhpq-testclient ./cmd/x3dhpq-testclient
