use jmaptest;

attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:submission',
  );

  # RFC 8620 S5.4/S5.5: "queryState" and the object "state" are separate opaque
  # strings, so fetch each from its own method rather than reusing one.
  my $res = $tester->request([[
    "EmailSubmission/query" => {},
  ]]);
  ok($res->is_success, "EmailSubmission/query baseline");
  my $query_state = $res->single_sentence("EmailSubmission/query")->arguments->{queryState};
  ok(defined $query_state, "got queryState");

  $res = $tester->request([[
    "EmailSubmission/get" => {},
  ]]);
  ok($res->is_success, "EmailSubmission/get baseline");
  my $state = $res->single_sentence("EmailSubmission/get")->arguments->{state};
  ok(defined $state, "got state");

  subtest "no changes from current state" => sub {
    my $res = $tester->request([[
      "EmailSubmission/queryChanges" => {
        sinceQueryState => $query_state,
      },
    ]]);
    ok($res->is_success, "EmailSubmission/queryChanges") or diag explain $res->response_payload;

    # RFC 8620 S5.6 allows cannotCalculateChanges here too.
    my $sent = $res->single_sentence;
    if ($sent->name eq 'error') {
      is($sent->arguments->{type}, 'cannotCalculateChanges',
         'the only acceptable error here is cannotCalculateChanges')
        or diag explain $sent->arguments;
      note("cannot calculate query changes from a queryState issued moments ago: within spec, but inefficient");
      return;
    }

    jcmp_deeply(
      $sent->arguments,
      superhashof({
        oldQueryState => jstr($query_state),
        newQueryState => jstr($query_state),
        added         => [],
        destroyed     => [],
      }),
      "no changes from current state",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "EmailSubmission/changes also returns no changes" => sub {
    my $res = $tester->request([[
      "EmailSubmission/changes" => {
        sinceState => $state,
      },
    ]]);
    ok($res->is_success, "EmailSubmission/changes") or diag explain $res->response_payload;

    # RFC 8620 S5.2 makes 30 days of history only a SHOULD, so a fresh state
    # may be uncalculable too.
    my $sent = $res->single_sentence;
    if ($sent->name eq 'error') {
      is($sent->arguments->{type}, 'cannotCalculateChanges',
         'the only acceptable error here is cannotCalculateChanges')
        or diag explain $sent->arguments;
      note("cannot calculate changes from a state issued moments ago: within spec, but inefficient");
      return;
    }

    jcmp_deeply(
      $sent->arguments,
      superhashof({
        oldState      => jstr($state),
        newState      => jstr($state),
        created       => [],
        updated       => [],
        destroyed     => [],
      }),
      "no changes from current state",
    ) or diag explain $res->as_stripped_triples;
  };
};
