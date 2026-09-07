# Writing a ServerAdapter

To run this suite against your own JMAP server you write one class: a
**server adapter**. It answers a single question for the harness — *give me an
account I can test against* — and hands back something that knows how to make
authenticated JMAP requests.

Everything else (what to create, what to assert, which tests to skip) is
already handled.

Contents:

- [The smallest adapter that works](#the-smallest-adapter-that-works)
- [Wiring it up](#wiring-it-up)
- [The account object](#the-account-object)
- [Optional capabilities, and what you lose without them](#optional-capabilities-and-what-you-lose-without-them)
- [How tests skip](#how-tests-skip)
- [Things that will bite you](#things-that-will-bite-you)
- [Checking your adapter](#checking-your-adapter)

---

## The smallest adapter that works

One required method on the adapter (`any_account`) and one on the account
(`authenticated_tester`). That is the whole contract.

Put it in `lib/JMAP/TestSuite/ServerAdapter/MyServer.pm`:

```perl
package JMAP::TestSuite::ServerAdapter::MyServer;
use Moose;
with 'JMAP::TestSuite::ServerAdapter';

# Whatever your config file provides, as Moose attributes.
has base_uri => (is => 'ro', required => 1);
has username => (is => 'ro', required => 1);
has password => (is => 'ro', required => 1);
has accountId => (is => 'ro', required => 1);

sub any_account {
  my ($self) = @_;

  return JMAP::TestSuite::Account::MyServer->new({
    server    => $self,
    accountId => $self->accountId,
  });
}

package JMAP::TestSuite::Account::MyServer {
  use Moose;
  with 'JMAP::TestSuite::Account';

  use MIME::Base64 qw(encode_base64);
  use JMAP::TestSuite::JMAP::Tester::WithSugar;

  sub authenticated_tester {
    my ($self) = @_;

    my $base  = $self->server->base_uri =~ s{/\z}{}r;
    my $creds = encode_base64($self->server->username . ':'
                            . $self->server->password, '');

    my $tester = JMAP::TestSuite::JMAP::Tester::WithSugar->new({
      api_uri      => "$base/jmap",
      upload_uri   => "$base/jmap/upload/{accountId}/",
      download_uri => "$base/jmap/download/{accountId}/{blobId}/{name}",
    });

    $tester->ua->set_default_header(Authorization => "Basic $creds");
    $tester->default_using([ 'urn:ietf:params:jmap:core',
                             'urn:ietf:params:jmap:mail' ]);

    return $tester;
  }

  no Moose;
  __PACKAGE__->meta->make_immutable;
}

no Moose;
__PACKAGE__->meta->make_immutable;
```

Use `JMAP::TestSuite::JMAP::Tester::WithSugar`, not `JMAP::Tester` directly —
the tests rely on the extra helpers it adds.

## Wiring it up

The adapter is chosen by a JSON config file. The `adapter` key names the class
after `JMAP::TestSuite::ServerAdapter::`; every other key is passed to the
constructor, so it must match a Moose attribute you declared.

```json
{
  "adapter"   : "MyServer",
  "base_uri"  : "http://localhost:8080",
  "username"  : "test@example.com",
  "password"  : "secret",
  "accountId" : "u123"
}
```

```sh
JMAP_SERVER_ADAPTER_FILE=my-server.json prove -Ilib -r t
```

Start with one file while you get it working:

```sh
JMAP_SERVER_ADAPTER_FILE=my-server.json prove -Ilib -v t/Mailbox/get/basic.t
```

## The account object

`any_account` returns an object doing the `JMAP::TestSuite::Account` role. That
role requires exactly one method, `authenticated_tester`, and gives you
everything the tests actually call: `create_mailbox`, `add_message_to_mailboxes`,
`import_messages`, `create_calendar`, `create_calendar_event`,
`create_address_book`, `create_contact_card`, `get_state`, and the
`create`/`retrieve` batch helpers.

You do not implement any of those. They are written in terms of JMAP method
calls through the tester you returned.

The `accountId` you pass must be the one your server uses in JMAP method
arguments — normally the value from `primaryAccounts` in the session resource,
which is not always the username. The account's tester injects it as the
default `accountId` argument of every method call, so you do not set
`default_arguments` on the tester yourself.

## Optional capabilities, and what you lose without them

Implement these as you are able. Each is optional; tests needing one skip
cleanly when it is absent, so a partial adapter is genuinely useful.

| Method | Returns | Without it |
|---|---|---|
| `any_account` | one account | **Required.** Nothing runs. |
| `pristine_account` | a guaranteed-empty account | Every test marked `attr pristine => 1` skips. That is a large fraction of the suite: anything creating named mailboxes, calendars or address books, because leftovers from a previous run make results ambiguous. |
| `pool_account_pair` | two accounts that can see each other | All cross-account `/copy` tests skip: `Email/copy`, `Blob/copy`, `CalendarEvent/copy`, `ContactCard/copy`. |

`pristine_account` is the one worth the effort. If your server can provision
users through an admin API, create a fresh one per call — that is what the
`Stalwart` and `CyrusDirect` adapters do:

```perl
our $STARTTIME = time();
our $USERNUM   = 1;

sub pristine_account {
  my ($self) = @_;
  my $name = "jt-$STARTTIME-$$-" . $USERNUM++;   # unique across parallel runs
  # ... create the user on your server, then:
  return JMAP::TestSuite::Account::MyServer->new({
    server    => $self,
    accountId => $account_id,
    username  => $name,
    password  => $pass,
  });
}
```

If you cannot provision users, do not fake it by reusing one account — the
skips are more useful than false results.

There is a fallback for the middle case. `unshared_account` is provided by the
role: it returns `pristine_account` if you have one, and otherwise takes an
exclusive file lock on `any_account` so two concurrent runs do not interleave.
That needs an `account-locks` directory to exist in the working directory.

Two further helpers, `same_creds_account_pair` and `mixed_account_pair`, exist
on the `JMAPProxy` and `CyrusDirect` adapters for proxy-specific scenarios. No
test in `t/` requires them, so you can ignore them unless you are testing a
proxy.

## How tests skip

Two independent mechanisms. Both are already used throughout the suite; you
only need to recognise them when reading results.

**Adapter capability.** A file starting with

```perl
attr pristine => 1;      # or: attr pool_pairs => 1;
```

skips entirely unless your adapter implements the matching method.

**Server capability.** Inside a test:

```perl
$tester->require_capabilities(
  'urn:ietf:params:jmap:core',
  'urn:ietf:params:jmap:calendars',
);
```

This compares against the tester's `default_using` list, so **that list must
reflect what your server actually advertises**. Build it from the session
resource rather than hardcoding, or you will either skip tests you could run or
run tests your server was never going to pass:

```perl
my @using = sort keys %{ $session->{capabilities} // {} };
$tester->default_using(\@using);
```

Note that `require_capabilities` also *replaces* `default_using` with the
capabilities it was given, so each test sends only the ones it needs.

## Things that will bite you

**Session URLs may not be reachable from the test runner.** A containerised
server often advertises its internal hostname in `apiUrl`, `uploadUrl` and
`downloadUrl`. The `Stalwart` adapter deliberately ignores those and rebuilds
every URL from `base_uri`. Do the same if your session URLs are not externally
resolvable.

**`accountId` is not the username.** Take it from `primaryAccounts` in the
session.

**Name accounts uniquely per run.** `"jt-$STARTTIME-$$-$n"` includes the pid, so
parallel runs and reruns do not collide. Reused names are the most common cause
of confusing failures.

**Fail loudly during provisioning.** If account creation half-works, the
failure surfaces much later in an unrelated assertion. Every provisioning step
in the shipped adapters dies with the HTTP status line on failure — copy that
habit.

**A failure is not automatically your bug.** Some are the suite reporting a
real gap in the server. `ROADMAP.md` lists four in Cyrus found this way,
including one where Cyrus accepts only the *obsoleted* plural
`recurrenceRules`. When a test fails, read the spec citation in its comments
first — every assertion added recently names the text it enforces.

## Checking your adapter

Work up in this order; each step exercises strictly more of the contract.

```sh
# 1. Can you talk to the server at all?
JMAP_SERVER_ADAPTER_FILE=my.json prove -Ilib -v t/core/jmap-session-resource.t

# 2. Basic reads.
JMAP_SERVER_ADAPTER_FILE=my.json prove -Ilib -r t/Mailbox

# 3. Writes and change tracking.
JMAP_SERVER_ADAPTER_FILE=my.json prove -Ilib -r t/Email

# 4. Everything.
JMAP_SERVER_ADAPTER_FILE=my.json prove -Ilib -r t
```

If you want a known-good baseline to compare against first, run the suite
against the Cyrus test container as described in `README.md`. Seeing what a
passing run looks like — and which failures are the backend's — makes your own
results much easier to read.
