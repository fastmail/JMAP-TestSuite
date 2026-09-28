# JMAP-TestSuite Design Review

Comparison of the original design goals (GitHub Issue #7) against the current
state of the codebase, plus a summary of open pull requests.

Review date: 2026-04-08

## Issue #7: Original Design Todo List

The issue (by rjbs) describes the intended scope of the test suite. For each
datatype, the suite should test create, update, delete, and change-tracking
operations with both happy-path and negative/constraint-violation cases.

Full text: https://github.com/fastmail/JMAP-TestSuite/issues/7

## Current Project Structure

```
t/
  core/               4 tests  (session resource, upload, download, backrefs)
  Email/             55 tests  (get, set/create, set/update, set/destroy,
                                import, query, queryChanges, changes)
  Mailbox/           20 tests  (get, set/create, set/update, set/destroy,
                                query, changes)
  Thread/             6 tests  (get, changes)
  basic.t, previews.t, etc.    (legacy/standalone tests)

lib/JMAP/TestSuite/
  ServerAdapter/      Adapter implementations (Simple, Cyrus, JMAPProxy, FastMail)
  Entity/             Email.pm, Mailbox.pm, Thread.pm
  Comparator/         Email.pm, Mailbox.pm, Thread.pm
  Account.pm          Test account interface (email blob generation, imports, etc.)
  Tester.pm           Test harness integrating Test::Routine with JMAP
```

Adapters are selected via a JSON config file pointed to by
`JMAP_SERVER_ADAPTER_FILE`. Four adapters exist: Simple (generic JMAP),
Cyrus (Cyrus IMAP), JMAPProxy (proxy-to-IMAP), and FastMail.

---

## Create Operations

| Design Goal | Status | Notes |
|---|---|---|
| Create with every allowed field specified | Partial | Email/set has 25 create tests covering body structure, headers, attachments. Mailbox/set has 2 create tests. |
| Create with only minimum specified | Done | `t/Email/set/create/minimum.t` and similar tests exist. |
| Created IDs appear in getFoosUpdates | Partial | `t/Email/changes/` (3 tests), `t/Mailbox/changes/` (4 tests), `t/Thread/changes/` (3 tests) cover this. |
| Backreference tree creation (parentId) | Partial | `t/core/backrefs-simple.t` tests basic backreferences, but no tree-of-mailboxes-with-backrefs test. |
| Constraint violation rejects create | Partial | Some validation tests exist (e.g. immutable fields in Mailbox) but not systematic across all fields. |
| Missing required field rejects create | Minimal | Not systematically tested for all required fields. |

## Update Operations

| Design Goal | Status | Notes |
|---|---|---|
| Reference created things in updates | Not tested | No test for "create mailbox, then move messages into it" in one request. |
| Constraint failures on update | Minimal | `t/Mailbox/set/update/` has 1 test. |
| Immutable field modification fails | Partial | Mailbox immutable fields tested, not comprehensive. |
| Non-existent ID gives sane notUpdated | Not tested | No dedicated test found. |

## Delete Operations

| Design Goal | Status | Notes |
|---|---|---|
| Deleting non-existent gives sane response | Not tested | No dedicated test. |
| Can't delete if still referenced | Done | `t/Mailbox/set/destroy/` has 4 tests including "with children" and "on-nonempty". |
| Normal delete works | Done | `t/Email/set/destroy/` and Mailbox destroy tests exist. |

## Change Tracking (getFoosUpdates)

| Design Goal | Status | Notes |
|---|---|---|
| Changes appear between pre/post states | Done | Email/changes, Mailbox/changes, Thread/changes all test this. |
| Container state changes on content add/delete | Partial | Some Mailbox changes tests exist, but not the full "QRESYNC tombstone" scenario described. |
| cannotCalculateUpdates handled gracefully | Not tested | No test for this response. |
| Server returning extra updates flagged as "inefficient" | Partial | Commit 5213643 allows spurious removals in queryChanges per RFC 8620 S5.6, which is aligned with this philosophy. |

## Datatype Coverage

| Datatype | Status | Notes |
|---|---|---|
| Email | Well covered | 55 tests across get/set/import/query/changes. |
| Mailbox | Moderately covered | 20 tests across get/set/query/changes. |
| Thread | Lightly covered | 6 tests (get + changes only; Thread/set doesn't exist since threads are implicit). |
| Calendar | Not merged | PR #27 adds basic CalendarEvent entity + tests but has requested changes and is stale (2019). |
| Contacts/Addressbook | Not present | Not implemented at all. |

---

## Open Pull Requests

### PR #21 - test a few ways to test and clear (keyword set/clear)
- Author: rjbs
- Status: Blocked -- Cyrus fails these tests. Stale since 2018.
- Adds 119 lines testing keyword on/off in ways that should and should not work.

### PR #22 - unshared accounts
- Author: rjbs
- Status: Stale since 2018.
- Large refactor (539 additions, 407 deletions) for testing unshared account access.

### PR #27 - Add basic Calendar support/tests
- Author: wolfsage (Matthew Horsfall)
- Status: Changes requested by rsto. Stale since 2019.
- Adds CalendarEvent entity, comparator, and basic tests (178 additions).

### PR #31 - Email/get: test for some trivial address group behaviors
- Author: rjbs
- Status: Open since 2019.
- Small addition (60 lines) testing address group handling in Email/get.

### PR #41 - JMAPProxy tests (current branch)
- Author: brong
- Status: Open, review requested from rjbs and wolfsage.
- Updates the JMAPProxy adapter and example config. Fixes tests that assumed
  things the JMAP spec doesn't guarantee (spurious deletes, blobId changes,
  accounts with no role=inbox auto-created). Adds squatter sleep for proxy.

---

## Key Gaps vs. the Design Vision

1. **Negative testing is thin.** The design calls for systematic constraint
   violation, missing-field, and non-existent-ID testing. Current tests are
   mostly happy-path.

2. **Cross-method workflows.** Creating + referencing in the same request
   (beyond basic backrefs) isn't well tested. The design specifically calls
   for "create a folder, move existing messages into it" in a single request.

3. **Container state tracking.** The "QRESYNC" scenario -- content changes
   cause the container's state to update, tombstones are tracked correctly --
   is only partially covered.

4. **Calendar/Contacts.** The design mentions "container types (Calendars,
   Addressbooks)" but only Mailboxes are implemented. The Calendar PR (#27)
   never landed.

5. **cannotCalculateUpdates.** No test handles this valid server response
   gracefully. The design specifically asks for this to be flagged as
   "inefficient server but within spec."

6. **Stale PRs.** PRs #21, #22, #27, and #31 represent partially-done work
   toward these goals that never landed. Some may need significant rework
   to apply cleanly.
