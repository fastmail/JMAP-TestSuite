# JMAP-TestSuite

A compliance test suite for [JMAP](https://jmap.io/) servers. Tests cover RFC 8620 (JMAP Core), RFC 8621 (JMAP Mail), and a range of JMAP extension drafts. The RFC and draft texts are in `specs/`.

---

## Installation

Requires Perl 5.14+. Install dependencies with [App::cpanminus](https://metacpan.org/pod/App::cpanminus):

```sh
cpanm --installdeps .
```

---

## How it works

Tests are run with `prove`. Every test file connects to a JMAP server via a *server adapter*, selected by pointing the `JMAP_SERVER_ADAPTER_FILE` environment variable at a JSON config file:

```sh
JMAP_SERVER_ADAPTER_FILE=eg/stalwart.json prove -Ilib t/
```

The `adapter` key in the JSON selects the adapter class
(`JMAP::TestSuite::ServerAdapter::<adapter>`). The remaining keys are
passed as constructor arguments.

Tests that require a pristine empty account (tagged `attr pristine => 1`)
are automatically skipped if the adapter does not implement `pristine_account`.
Tests that require two shared accounts are skipped without `pool_account_pair`.

### Testing your own server

The adapters below are the ones that ship with the suite. To run it against a
server that isn't listed, write an adapter for it — that means implementing one
required method, and as many optional ones as your server can support.

**See [docs/writing-a-server-adapter.md](docs/writing-a-server-adapter.md)** for
the contract, a working skeleton, what each optional capability buys you, and
the mistakes that cost the most time.

---

## Backends

### Stalwart

[Stalwart](https://stalw.art/) is an open-source JMAP mail server with an
official Docker image.

**1. Start the container**

```sh
cd dev/stalwart
docker compose up -d
```

This uses `stalwartlabs/stalwart:latest` on port 8090 (configurable via
`STALWART_HTTP_PORT` in `dev/stalwart/.env`).

**2. Initialise the test domain (first time only)**

```sh
dev/stalwart/init.sh
```

This creates the `example.test` domain via Stalwart's admin API. It is
idempotent — safe to run again.

**3. Run the tests**

```sh
JMAP_SERVER_ADAPTER_FILE=eg/stalwart.json prove -Ilib t/
```

**Config (`eg/stalwart.json`):**

```json
{
  "adapter"     : "Stalwart",
  "base_uri"    : "http://localhost:8090",
  "admin_user"  : "admin",
  "admin_pass"  : "changeme",
  "test_domain" : "example.test"
}
```

The adapter creates a fresh account per test that needs one (`pristine_account`).
Supports: `any_account`, `pristine_account`.
Does not support: `pool_account_pair`.

To use a different port, edit `dev/stalwart/.env` or set `STALWART_HTTP_PORT`
in your environment before `docker compose up`.

---

### CyrusDirect

Targets a [Cyrus IMAP](https://www.cyrusimap.org/) server that exposes both
a JMAP HTTP interface and a management REST API. The
[cyrus-docker-test-image](https://github.com/cyrusimap/cyrus-docker-test-image)
project provides a suitable container.

**1. Start the container** (see that project's README for the exact command)

**2. Configure**

Create a JSON config pointing at your running instance:

```json
{
  "adapter"      : "CyrusDirect",
  "base_uri"     : "http://localhost:8080",
  "mgmt_uri"     : "http://localhost:8001",
  "accountIds"   : ["testuser@localhost"],
  "cyrus_host"   : "localhost",
  "cyrus_port"   : 1143,
  "cyrus_admin_user" : "admin",
  "cyrus_admin_pass" : "admin"
}
```

**3. Run the tests**

```sh
JMAP_SERVER_ADAPTER_FILE=my-cyrusdirect.json prove -Ilib t/
```

Supports: `any_account`, `pristine_account`, `pool_account_pair`.

---

### Cyrus (with saslpasswd2)

Targets a locally installed Cyrus IMAP server. `pristine_account` uses
`saslpasswd2` to create SASL credentials and connects to IMAP as admin to
create mailboxes. Use this adapter when running against a Cyrus instance
installed on the test machine rather than via Docker.

**Config (`eg/cyrus.json`):**

```json
{
  "adapter"   : "Cyrus",
  "base_uri"  : "http://localhost",
  "credentials" : [{
    "username": "example@localhost",
    "password": "mypassword"
  }],
  "virtual_domain_enabled": 1
}
```

Additional optional keys: `cyrus_host`, `cyrus_port`, `cyrus_admin_user`,
`cyrus_admin_pass`, `cyrus_admin_use_ssl`, `saslpasswd2_path`, `no_sasl`.

Supports: `any_account`, `pristine_account`.

---

### Simple

The simplest adapter — no account creation, just static credentials. Use this
when you have a pre-existing JMAP account and just want to run tests against it.
Tests requiring `pristine_account` will be skipped.

**Config:**

```json
{
  "adapter"    : "Simple",
  "authentication_uri" : "http://localhost/.well-known/jmap",
  "credentials" : [{
    "accountId" : "myaccount",
    "username"  : "user@example.com",
    "password"  : "secret"
  }]
}
```

Supports: `any_account` only.

---

### JMAPProxy

Targets a [JMAP Proxy](https://github.com/jmapio/jmap-perl) server backed
by a Cyrus IMAP server. Creates accounts by provisioning both the IMAP mailbox
and the proxy's account registry. See `eg/proxy.json` for a full example config.

Supports: `any_account`, `pristine_account`, `pool_account_pair`.

---

### FastMail

Targets FastMail's JMAP API. Uses FastMail's proprietary session authentication
rather than RFC 8620 JMAP session discovery. Requires a real FastMail account.

Supports: `any_account` only.

---

## Running tests

Run all tests:

```sh
JMAP_SERVER_ADAPTER_FILE=eg/stalwart.json prove -Ilib t/
```

Run a specific suite in parallel:

```sh
JMAP_SERVER_ADAPTER_FILE=eg/stalwart.json prove -Ilib -j4 t/Mailbox/
```

Run a single test:

```sh
JMAP_SERVER_ADAPTER_FILE=eg/stalwart.json prove -Ilib t/Mailbox/get/some-entities.t
```

---

## Environment variables

| Variable | Description |
|---|---|
| `JMAP_SERVER_ADAPTER_FILE` | Path to the JSON adapter config file **(required)** |
| `JMTS_USE_WEBSOCKETS` | Set to `1` to use WebSocket transport (Cyrus adapters only) |
| `JMTS_TELEMETRY` | Set to `1` to log HTTP requests to stderr |
| `JMTS_TEST_OUTPUT_TO_STDERR` | Set to `1` to send TAP output to stderr |

---

## Interpreting results

- **PASS** — the server behaves as the JMAP spec requires.
- **SKIP** — the test needs a capability or adapter feature not available (e.g. `pristine_account`, a specific JMAP capability).
- **FAIL** — the server deviates from the spec. This is the whole point: failures are findings, not breakage in the test suite.
