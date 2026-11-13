use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:submission',
  );

  my $res = $tester->request([[
    "Identity/get" => {},
  ]]);
  ok($res->is_success, "Identity/get");
  my $state = $res->single_sentence("Identity/get")->arguments->{state};
  ok(defined $state, "got state");

  subtest "changes from current state" => sub {
    my $res = $tester->request([[
      "Identity/changes" => { sinceState => $state },
    ]]);
    ok($res->is_success, "Identity/changes") or diag explain $res->response_payload;

    my $changes = $res->single_sentence("Identity/changes")->arguments;

    jcmp_deeply(
      $changes,
      superhashof({
        oldState => jstr($state),
        newState => jstr,
        created  => [],
        updated  => [],
        destroyed => [],
      }),
      "no changes from current state",
    ) or diag explain $res->as_stripped_triples;

    # RFC 8620 S5.1: servers SHOULD return the same state if nothing changed.
    note("newState differs from oldState though nothing changed (a SHOULD)")
      if ($changes->{newState} // q{}) ne $state;
  };

  subtest "cannotCalculateChanges for wrong state" => sub {
    my $res = $tester->request([[
      "Identity/changes" => { sinceState => 'bogus-state-xyz' },
    ]]);
    ok($res->is_success, "request succeeded");

    my $sent = $res->single_sentence;
    is($sent->name, 'error', "got error response");
    # A state the server never issued may be rejected as invalidArguments
    # rather than cannotCalculateChanges; both tell the client to resync.
    ok((grep { $sent->arguments->{type} eq $_ } qw(cannotCalculateChanges invalidArguments)),
       "cannotCalculateChanges or invalidArguments for a state never issued")
      or diag explain $sent->arguments;
  };
};
