use jmaptest;

attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mb_a = $account->create_mailbox({ name => 'aaa-queryChanges' });
  my $mb_b = $account->create_mailbox({ name => 'bbb-queryChanges' });

  my %args = (
    sort => [{ property => 'name', isAscending => jtrue() }],
  );

  my $res = $tester->request([[
    "Mailbox/query" => \%args,
  ]]);
  ok($res->is_success, "Mailbox/query baseline") or diag explain $res->response_payload;

  my $base = $res->single_sentence("Mailbox/query")->arguments;
  ok($base->{canCalculateChanges}, "canCalculateChanges is true");

  my $query_state = $base->{queryState};
  ok(defined $query_state, "got queryState");

  subtest "no changes" => sub {
    my $res = $tester->request([[
      "Mailbox/queryChanges" => {
        %args,
        sinceQueryState => $query_state,
      },
    ]]);
    ok($res->is_success, "Mailbox/queryChanges") or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("Mailbox/queryChanges")->arguments,
      superhashof({
        oldQueryState => jstr($query_state),
        newQueryState => jstr($query_state),
        added         => [],
        removed       => [],
      }),
      "no-changes response",
    ) or diag explain $res->as_stripped_triples;
  };

  # Create a mailbox that sorts between a and b
  my $mb_new = $account->create_mailbox({ name => 'aab-queryChanges' });

  subtest "created mailbox appears in added" => sub {
    my $res = $tester->request([[
      "Mailbox/queryChanges" => {
        %args,
        sinceQueryState => $query_state,
      },
    ]]);
    ok($res->is_success, "Mailbox/queryChanges") or diag explain $res->response_payload;

    my $args_out = $res->single_sentence("Mailbox/queryChanges")->arguments;
    jcmp_deeply(
      $args_out,
      superhashof({
        oldQueryState => jstr($query_state),
        newQueryState => none(jstr($query_state)),
        added         => supersetof(superhashof({ id => jstr($mb_new->id) })),
        removed       => ignore,
      }),
      "new mailbox in added",
    ) or diag explain $res->as_stripped_triples;

    $query_state = $args_out->{newQueryState};
  };

  $tester->request_ok(
    [ "Mailbox/set" => { destroy => [ $mb_a->id ] } ],
    superhashof({ destroyed => [ $mb_a->id ] }),
    "destroyed mailbox",
  );

  subtest "destroyed mailbox appears in removed" => sub {
    my $res = $tester->request([[
      "Mailbox/queryChanges" => {
        %args,
        sinceQueryState => $query_state,
      },
    ]]);
    ok($res->is_success, "Mailbox/queryChanges") or diag explain $res->response_payload;

    # RFC 8620 S5.5: queryState MUST change when the matching ids change, so a
    # removal reported under an unchanged state would be reported forever.
    jcmp_deeply(
      $res->single_sentence("Mailbox/queryChanges")->arguments,
      superhashof({
        oldQueryState => jstr($query_state),
        newQueryState => none(jstr($query_state)),
        removed       => supersetof($mb_a->id),
        added         => ignore,
      }),
      "destroyed mailbox in removed",
    ) or diag explain $res->as_stripped_triples;
  };
};
