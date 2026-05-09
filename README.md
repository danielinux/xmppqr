# xmppqr

`xmppqr` is an XMPP server that uses `wolfSSL`/`wolfCrypt` for TLS and cryptographic primitives, with an experimental post-quantum end-to-end encryption stack under active development.

This README is intentionally operational. It covers installation, configuration, running the server, account management, and client troubleshooting. Protocol design details live in [docs/x3dhpq-xep-draft.md](./docs/x3dhpq-xep-draft.md) and federation notes live in [docs/federation.md](./docs/federation.md).

## License

**AGPLv3.** See [LICENSE](./LICENSE).

## Status

`xmppqr` is still **pre-alpha**, but the repository is no longer just a design stub. The current tree contains:

- `xmppqrd`: the server daemon
- `xmppqrctl`: the admin CLI for migrations, user management, and TLS probing
- PostgreSQL-backed persistent storage
- client-to-server listeners for STARTTLS and direct TLS
- WebSocket XMPP transport
- message archive management, PEP, roster/presence, message carbons, push hooks, MUC, stream management, and in-band registration
- server-to-server federation with STARTTLS and dialback
- the in-repo `x3dhpq` implementation and test client

Important caveats for operators right now:

- There are no release artifacts or distro packages yet. Installation is from source.
- The daemon can still create a developer bootstrap user via `-dev-user` and `-dev-pass`, but it no longer does so automatically.
- The daemon requires an explicit TLS certificate and key. It does not generate development certificates.
- The default database driver is in-memory. That is convenient for development, but it is not persistent and `xmppqrctl` intentionally refuses to manage users against it.
- The project is moving quickly. Expect config and runtime behavior to continue changing.

## What To Read

- Use this README for deployment and operations.
- Use [docs/federation.md](./docs/federation.md) for S2S setup and dialback behavior.
- Use [docs/x3dhpq-xep-draft.md](./docs/x3dhpq-xep-draft.md) for the protocol and trust model.

## Prerequisites

Source builds currently require:

- Go `1.26+`
- `pkg-config`
- PostgreSQL `15+` for persistent storage
- wolfSSL development headers and library visible through `pkg-config wolfssl`

The wolfCrypt wrappers in this tree are targeted at wolfSSL `5.9.1`. The code uses cgo, so `pkg-config --cflags --libs wolfssl` must work on the build host.

Features currently used in-tree include:

- TLS 1.2/1.3
- X25519
- Ed25519
- HKDF
- AES-GCM
- HMAC / SHA-2
- ML-KEM-768

ML-DSA support is also wired into the tree, but whether it works on your machine depends on how your local wolfSSL was built.

## Build

After cloning the repository, build working binaries with the local wolfSSL
wrapper:

```bash
git clone https://github.com/danielinux/xmppqr
cd xmppqr
./scripts/build-xmppqrd-local-wolfssl.sh
```

That produces `./xmppqrd`, `./xmppqrctl`, and `./x3dhpq-testclient` linked
against a local static wolfSSL build.

If your system wolfSSL has all required features available through
`pkg-config wolfssl`, you can build directly against the system library:

```bash
go build -o ./xmppqrd ./cmd/xmppqrd
go build -o ./xmppqrctl ./cmd/xmppqrctl
go build -o ./x3dhpq-testclient ./cmd/x3dhpq-testclient
```

The default wolfSSL ref is `v5.9.1-stable`. You can override it with a
positional argument:

```bash
./scripts/build-xmppqrd-local-wolfssl.sh v5.9.1-stable
```

or with the ignored root `.env` file:

```bash
XMPPQR_WOLFSSL_REF=v5.9.1-stable
```

The scripts download the selected wolfSSL tag archive into `.local/src`, install
wolfSSL into `.local/wolfssl-<ref>` by default, for example
`.local/wolfssl-v5.9.1-stable`, and run the Go builds with
`PKG_CONFIG_LIBDIR` pointing at that local `wolfssl.pc`. Set
`XMPPQR_WOLFSSL_PREFIX` in the shell or `.env` to override the install
directory. Plain `go build` continues to use the system `pkg-config wolfssl`
configuration.

If you only want to check the admin CLI path:

```bash
go test ./cmd/xmppqrctl/...
```

## Installation Layout

A minimal source install usually looks like this:

```text
/etc/xmppqr/xmppqrd.yaml
/etc/xmppqr/tls/cert.pem
/etc/xmppqr/tls/key.pem
/usr/local/bin/xmppqrd
/usr/local/bin/xmppqrctl
```

## TLS Files

`xmppqrd` requires these files to exist before startup:

```text
/etc/xmppqr/tls/cert.pem
/etc/xmppqr/tls/key.pem
```

How those files are produced is outside the scope of `xmppqr` itself. The daemon just reads PEM files from the configured paths.

For local testing, a self-signed certificate is fine. One simple manual flow is:

```bash
install -d /etc/xmppqr/tls
openssl req -x509 -newkey rsa:2048 -nodes \
  -days 30 \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost" \
  -keyout /etc/xmppqr/tls/key.pem \
  -out /etc/xmppqr/tls/cert.pem
chmod 600 /etc/xmppqr/tls/key.pem
```

If you want local clients to trust that `localhost` certificate through the system trust store, install the certificate, not the private key:

```bash
cp /etc/xmppqr/tls/cert.pem /usr/local/share/ca-certificates/xmppqr-localhost.crt
update-ca-certificates
```

Notes:

- Modern clients expect `localhost` to appear in `subjectAltName`; `CN=localhost` alone is not enough.
- If you regenerate the self-signed certificate later, repeat the trust-store update step.
- Some clients use their own certificate store rather than the OS trust store, so you may still need to import the certificate in the client itself.

For real deployments, use your normal certificate management flow instead, for example Let's Encrypt or another ACME client. In that case, point `tls.cert_file` and `tls.key_file` at the live certificate and private key paths you already manage on the host, or copy/symlink them into `/etc/xmppqr/tls/`.

Practical guidance:

- Use a self-signed certificate only for local development or controlled client testing.
- Use a publicly trusted certificate for normal client and federation traffic.
- Make sure the certificate CN/SAN matches the hostname clients and remote servers actually connect to.
- Keep the private key readable only by the account running `xmppqrd`.

One practical flow is:

```bash
install -d /etc/xmppqr /etc/xmppqr/tls
cp internal/config/example.yaml /etc/xmppqr/xmppqrd.yaml
install -m 0755 ./xmppqrd /usr/local/bin/xmppqrd
install -m 0755 ./xmppqrctl /usr/local/bin/xmppqrctl
```

## Configuration

Start from the sample file at [internal/config/example.yaml](/home/dan/src/xmppqr/internal/config/example.yaml).

The main sections are:

- `server`: XMPP domain and host identity
- `listeners`: C2S, S2S, upload, metrics, and optional WebSocket enablement
- `tls`: certificate paths and PQ-hybrid preference
- `db`: storage backend
- `log`: level, format, stanza redaction
- `modules`: feature toggles and limits
- `s2s`: federation settings

Minimal persistent configuration:

```yaml
server:
  domain: example.com
  hostname: xmpp.example.com
  resource_prefix: xmppqr

listeners:
  c2s_starttls: ":5222"
  c2s_directtls: ":5223"
  s2s: ":5269"
  http_upload: ":5443"
  admin_pprof: "127.0.0.1:6060"
  websocket: ""

tls:
  cert_file: /etc/xmppqr/tls/cert.pem
  key_file: /etc/xmppqr/tls/key.pem
  min_version: TLS1.2
  prefer_pq_hybrid: true

db:
  driver: postgres
  dsn: "host=127.0.0.1 port=5432 user=xmppqr password=secret dbname=xmppqr sslmode=disable"
  max_conns: 20
  migrate_on_start: true

log:
  level: info
  format: text
  redact_stanzas: true

modules:
  mam: true
  push: true
  carbons: true
  muc: true
  http_upload: true
  pep: true
  sm: true
  csi: true
  ibr: false
  x3dhpq_item_max_bytes: 262144

s2s:
  enabled: false
  dialback_enabled: true
  insecure_skip_verify: false
  allowed_domains: []
```

Notes that matter in practice:

- `server.domain` is required and must match the XMPP domain clients use in their JIDs.
- At least one of `listeners.c2s_starttls`, `listeners.c2s_directtls`, or `listeners.s2s` must be set.
- `tls.cert_file` and `tls.key_file` are required by `xmppqrd` and must point to readable PEM files.
- `db.driver: memory` is useful only for throwaway local testing.
- `admin_pprof` serves both Prometheus metrics at `/metrics` and Go pprof handlers. Keep it loopback-only unless you really mean to expose it.
- The HTTP upload and WebSocket server is plain HTTP inside the daemon. If you expose it on the internet, put it behind TLS termination or a reverse proxy.

## Database Setup

Create a PostgreSQL database and role:

```sql
CREATE ROLE xmppqr LOGIN PASSWORD 'secret';
CREATE DATABASE xmppqr OWNER xmppqr;
```

Then either let the daemon migrate automatically with `db.migrate_on_start: true`, or run migrations manually:

```bash
xmppqrctl migrate -config /etc/xmppqr/xmppqrd.yaml
```

When using PostgreSQL, both `xmppqrd` and `xmppqrctl` normalize legacy localpart-only usernames to bare JIDs using `server.domain`. For example, an older `test` row becomes `test@example.com`.

## Running The Server

Development run with defaults:

```bash
./xmppqrd -config /etc/xmppqr/xmppqrd.yaml
```

What that does by default:

- uses `localhost` as the domain if none is configured
- listens on `:5222` and `:5223`
- uses `/etc/xmppqr/tls/cert.pem` and `/etc/xmppqr/tls/key.pem` unless overridden in config
- does not create any users unless you explicitly pass `-dev-user`
- uses the database configured in `/etc/xmppqr/xmppqrd.yaml`

Configured run:

```bash
xmppqrd -config /etc/xmppqr/xmppqrd.yaml -dev-user bootstrap -dev-pass 'change-me-now'
```

If you choose to use the bootstrap-user path, set `-dev-user` and `-dev-pass` deliberately and rotate or remove that account after initial setup.

Useful listeners:

- `5222`: client-to-server STARTTLS
- `5223`: client-to-server direct TLS
- `5269`: server-to-server federation
- `5443`: HTTP upload service and, if enabled, `/xmpp-websocket`
- `127.0.0.1:6060`: metrics and pprof by default

## User Management

Persistent user management currently goes through `xmppqrctl` and PostgreSQL.

Create a user:

```bash
xmppqrctl useradd alice
```

Or pass the password non-interactively:

```bash
xmppqrctl useradd alice -password 'correct horse battery staple'
```

Replace an existing user:

```bash
xmppqrctl useradd alice -password 'new-password' -replace
```

List users:

```bash
xmppqrctl userlist
```

Delete a user:

```bash
xmppqrctl userdel alice
```

Operational details:

- The canonical account key is the bare JID. `xmppqrctl useradd alice` stores `alice@<server.domain>`.
- `xmppqrctl` auto-loads config from `XMPPQR_CONFIG`, then `./xmppqrd.yaml`, then `/etc/xmppqr/xmppqrd.yaml`, unless `-config` is passed explicitly.
- `xmppqrctl` requires `db.driver: postgres`. It will fail on the in-memory backend by design.
- Passwords are stored as SCRAM-SHA-256 and SCRAM-SHA-512 material plus an Argon2-style storage hash payload used by the server code.

## Client Configuration

For a normal XMPP client, configure:

- JID: `alice@example.com`
- Username: `alice`
- Domain: `example.com`
- Password: the password set with `xmppqrctl`
- Host: the server that presents the certificate for `example.com`
- Port: `5222` for STARTTLS or `5223` for direct TLS

Authentication currently includes:

- `SCRAM-SHA-512-PLUS`
- `SCRAM-SHA-256-PLUS`
- `SCRAM-SHA-512`
- `SCRAM-SHA-256`
- `PLAIN` for legacy clients

If you enable in-band registration with `modules.ibr: true`, clients can also try account creation through XMPP itself. For stable deployments, admin-created accounts are the safer path today.

## WebSocket Transport

If `listeners.websocket` is non-empty, `xmppqrd` enables XMPP-over-WebSocket at:

```text
/xmpp-websocket
```

Current behavior to know:

- the WebSocket request must include `Sec-WebSocket-Protocol: xmpp`
- the handler is served by the same HTTP server as file upload
- SCRAM-PLUS channel binding is not available over WebSocket because the TLS exporter is not exposed through `net/http`

In practice, terminate HTTPS in a reverse proxy and forward WebSocket traffic to the daemon.

## Federation

Federation support is present and documented separately in [docs/federation.md](./docs/federation.md).

At a high level today:

- outbound and inbound S2S use STARTTLS
- dialback is the main authentication mechanism
- optional mTLS wiring exists in config
- remote-domain allowlisting is supported

For deployment, you still need the standard XMPP DNS and certificate hygiene:

- `A`/`AAAA` records for the host
- `_xmpp-server._tcp` SRV if you do not use the default host/port
- certificates whose names match what peers connect to

## Troubleshooting

### The client cannot log in

Check the basics first:

- the client JID domain matches `server.domain`
- the user exists in PostgreSQL, not only in a previous in-memory run
- the password was set against the same config file the daemon is using
- the client is using the correct port and TLS mode

Useful commands:

```bash
xmppqrctl userlist
xmppqrctl tls-probe xmpp.example.com:5223
```

### `xmppqrctl useradd` says the storage backend is invalid

That usually means the config still points at:

```yaml
db:
  driver: memory
```

Switch to PostgreSQL and run migrations.

### Users disappear after restart

You are running the memory backend. That is expected. Configure:

```yaml
db:
  driver: postgres
```

### TLS fails or clients reject the certificate

Common causes:

- the configured cert or key path is wrong or unreadable
- the certificate CN/SAN does not match the hostname clients connect to
- the client is pointed at the wrong host for the JID domain

Use:

```bash
xmppqrctl tls-probe xmpp.example.com:5223
```

That prints the negotiated protocol version, cipher, named group, whether PQ-hybrid key exchange was used, and peer certificate count.

### STARTTLS works but direct TLS does not, or vice versa

Verify which listener the client is using:

- `5222` expects plain TCP followed by STARTTLS
- `5223` expects TLS immediately

Using the wrong mode on the right port will fail before authentication.

### WebSocket clients fail immediately

Check all of the following:

- the WebSocket client is connecting to `/xmpp-websocket`
- it sends `Sec-WebSocket-Protocol: xmpp`
- you terminated HTTPS in front of the daemon if the client expects `wss://`

### Registration works nowhere

In-band registration is only advertised when `modules.ibr: true`.

### HTTP upload links are wrong or unusable

The current upload service builds URLs from `listeners.http_upload` and serves plain HTTP from the daemon. If you deploy behind a reverse proxy or external TLS terminator, make sure your public URL layout matches what clients receive, or front it with a consistent public endpoint.

### Federation does not come up

Check:

- `s2s.enabled: true`
- TCP `5269` reachability
- DNS SRV or fallback host resolution
- a certificate peers accept

Then read [docs/federation.md](./docs/federation.md) for the current dialback and STARTTLS behavior.

## Observability

By default the admin listener exposes:

- Prometheus metrics at `http://127.0.0.1:6060/metrics`
- Go pprof at `http://127.0.0.1:6060/debug/pprof/`

Keep `log.redact_stanzas: true` unless you are actively debugging protocol flow and accept the privacy trade-off.

## Current Gaps

This repo is advancing quickly, but it is not a finished production server yet. The main operational gaps today are:

- no packaged releases
- no polished service manager units or installer
- bootstrap-user path still exists for development
- HTTP upload and WebSocket deployment still expect operator-side proxying/TLS decisions
- ongoing churn in the x3dhpq feature set

If you want to evaluate it now, the most realistic path is: build from source, use PostgreSQL, run explicit TLS certs, create accounts with `xmppqrctl`, and keep the deployment small and supervised.
