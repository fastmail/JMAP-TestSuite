# JMAP-TestSuite Roadmap

`DESIGN-REVIEW.md` compares the suite against its original scope (upstream
issue #7). This file records what came out of that review: the decisions worth
knowing before changing an assertion, what the suite has found in real servers,
and what is still missing.

---

## Where the suite deliberately accepts more than one answer

These look like laxity and are not. Each is an option the spec explicitly
grants a server, so asserting a single outcome would manufacture a false
failure — which costs more than a missing test. A gap is a known gap; a false
failure is a bug report filed against correct code.

- **`cannotCalculateChanges`** (`t/{Email,Mailbox}/changes/`,
  `t/EmailSubmission/changes/`). RFC 8620 S5.2 makes 30 days of history a
  SHOULD, and no test can force a state to age out. So a fresh state may draw
  either a well-formed changes response or a proper `cannotCalculateChanges`;
  only a state that was never issued must produce the error.

- **A card in two address books** (`t/AddressBook/set/destroy.t`). RFC 9610
  S2.1 requires a card to belong to *at least one* address book and never
  obliges a server to support several. The subtest skips with a note if the
  server declines.

- **The error for a missing required property**
  (`t/Mailbox/set/create/missing-required-fields.t`). RFC 8620 S5.3 defines
  `invalidProperties` but lets a method define a more specific error that MUST
  then be used instead. The test insists the create is *rejected*, and checks
  the `properties` list only when the server does answer `invalidProperties`.

## An open question worth asking the WG

Adding the *first* `recurrenceOverrides` entry by pointer patch fails.
RFC 8620 S5.3 requires a patch pointer's parent to already exist, and
`recurrenceOverrides` is optional with no default, so when absent it does not
exist and `recurrenceOverrides/<id>` is an invalid patch. Cyrus rejects it;
that is a defensible reading, and jmap-calendars S5.9.1 does not lift the
rule.

But it is a trap: a client that has never overridden an occurrence cannot add
its first override the same way it adds its second, and must send the whole
`recurrenceOverrides` object instead. Note that the key itself is never the
problem -- jscalendarbis says a recurrence id that matches no occurrence is
simply treated as an additional occurrence -- so this is purely about the
parent property's existence.

`t/CalendarEvent/set/update.t` seeds the property at creation so it tests
override patching rather than this ambiguity.

## Where it is deliberately strict

- **`CalendarRights.mayShare`** — `draft-ietf-jmap-calendars` defines exactly
  eight rights and this is one of them. Renamed from `mayAdmin` in draft-22+;
  Cyrus adopted it in June 2026, so only builds older than that fail here.

- **`CalendarEvent.isDraft`** — required, and it should stay that way.
  CalendarEvent/get says `id`, `calendarIds`, `isDraft` and `isOrigin` MUST be included on every
  object returned by `CalendarEvent/get` with null or omitted `properties`. It
  is easy to mistake this for optional by reading the CalendarEvent/parse
  section, which is about parsing, where those four are null. Relaxing it would let a
  non-conformant server pass.

## Findings against Cyrus

Verified 2026-09-06 against Cyrus built from master (3.13.7-547), **not** the
published `cyrus-docker-test-server:latest`, which is a build from April and
five months behind. Testing against that image reports several gaps that were
fixed upstream months ago; build the image from current source before
believing any finding here.

Fixed upstream since the April image, listed so nobody re-reports them:
`mayShare` (was `mayAdmin`, June 2026), `Identity/changes` (implemented July
2026), and the singular `recurrenceRule` (current Cyrus accepts it and
rejects the obsoleted plural, which is correct).

Calendars and contacts:

- **`CalendarEvent/query` rejects `inCalendar`, `after` and `before`** with
  `invalidArguments`, though all three are normative FilterConditions of
  CalendarEvent/query. — `CalendarEvent/query/basic`,
  `CalendarEvent/query/expand-recurrences`, `CalendarEvent/queryChanges/basic`
- **Patching `recurrenceOverrides` does not take effect.** —
  `CalendarEvent/set/update`
- **No cross-account calendars or contacts.** `Calendar/get` on another
  account answers `accountNotSupportedByMethod`, and `AddressBook/get` shows
  only the Default book with `mayWriteAll` false, so cross-account copy
  cannot work. Granting the ACL on the DAV collections does not change it.
  The copy tests detect this and skip.

Mail:

- **`Email/query` ignores `hasAttachment`.** `Email/get` reports
  `hasAttachment: true` with one attachment for the same message, so the
  server contradicts itself. — `Email/query/filtering`
- **`Mailbox/queryChanges` reports a removal without advancing the state**:
  `removed` is non-empty while `newQueryState` equals `oldQueryState`. —
  `Mailbox/queryChanges/basic`
- **`preview` is always empty**, even after squatter has indexed the mailbox.
  Permitted by RFC 8621, which sets no minimum, but not useful.

Submission, MDN and quota:

- **`EmailSubmission/get` cannot find a submission it just created.**
  `EmailSubmission/set` returns a created id; `/get` on that exact id returns
  it in `notFound`. — `EmailSubmission/get/basic`
- **`EmailSubmission/changes` and `/queryChanges`** answer
  `cannotCalculateChanges` even for a state issued moments earlier.
- **`Identity/set` is `unknownMethod`**, though RFC 8621 defines it as a
  standard method of the submission capability, which Cyrus advertises.
  (`Identity/changes` is implemented as of July 2026.) — `Identity/set`
- **`MDN/parse` cannot parse a conformant MDN.** A canonical RFC 8098
  multipart/report comes back in `notParsable`; adding Date and Message-ID,
  or using the canonical `MDN-sent-manually` spelling, does not help. —
  `MDN/parse/basic`
- **`Quota/get` and `Quota/query` return nothing** although the account has
  an IMAP quota (`getquotaroot` shows `STORAGE 0 102400`). — `Quota/get`,
  `Quota/query`

Fixed in Cyrus while writing these tests, so only older builds fail them:
the `calendarHasEvents` error code (the registry defines the singular
`calendarHasEvent`) and `Email/import` returning `{}` where RFC 8621 types
`created`/`notCreated` as nullable.

Environment, not a server bug:

- **`SearchSnippet/get/basic` is flaky** (FAIL/PASS/FAIL in isolation). Cyrus
  is configured with `search_engine: xapian` and a `squatter` sync channel,
  but no squatter is running in the container, so indexing is whatever
  happens to have been done. Run
  `docker exec <container> su cyrus -s /bin/sh -c /usr/cyrus/sbin/squatter`
  before believing a snippet failure.

## Still missing

- **The four stale upstream PRs** — #21, #22 and #31 (2018–19), and #27, whose
  Calendar work is superseded by the coverage now in tree.
- **WebSocket coverage.** `JMTS_USE_WEBSOCKETS` and `can_use_websockets` exist,
  but no test exercises the transport specifically.
