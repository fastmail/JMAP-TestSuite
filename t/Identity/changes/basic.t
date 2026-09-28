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

    jcmp_deeply(
      $res->single_sentence("Identity/changes")->arguments,
      superhashof({
        oldState => jstr($state),
        newState => jstr($state),
        created  => [],
        updated  => [],
        destroyed => [],
      }),
      "no changes from current state",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "cannotCalculateChanges for wrong state" => sub {
    my $res = $tester->request([[
      "Identity/changes" => { sinceState => 'bogus-state-xyz' },
    ]]);
    ok($res->is_success, "request succeeded");

    my $sent = $res->single_sentence;
    is($sent->name, 'error', "got error response");
    is($sent->arguments->{type}, 'cannotCalculateChanges', "cannotCalculateChanges");
  };
};
