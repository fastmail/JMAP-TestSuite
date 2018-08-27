use jmaptest;

test {
  my ($self) = @_;

  # XXX - Skip if the server under test doesn't support it

  my $account = $self->any_account;
  my $tester  = $account->tester;

  # Create two mailboxes so we should have 3 states (start state,
  # new mailbox 1 state, new mailbox 2 state). Then, ask for changes
  # from start state, with a maxChanges set to 1 so we should get
  # hasMoreChanges when sinceState is start state.

  my $start_state = $account->get_state('mailbox');

  my $mailbox1 = $account->create_mailbox;

  my $mailbox2 = $account->create_mailbox;

  my $end_state = $account->get_state('mailbox');

  my $middle_state;

  subtest "changes from start state" => sub {
    my $res = $tester->request([[
      "Mailbox/changes" => {
        sinceState => $start_state,
        maxChanges => 1,
      },
    ]]);
    ok($res->is_success, "Mailbox/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/changes")->arguments,
      superhashof({
        accountId      => jstr($account->accountId),
        oldState       => jstr($start_state),
        newState       => all(jstr, none($start_state, $end_state)),
        hasMoreChanges => jtrue,
        created        => [ $mailbox1->id ],
        updated        => [],
        destroyed      => [],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;

    $middle_state = $res->single_sentence->arguments->{newState};
    ok($middle_state, 'grabbed middle state');
  };

  subtest "changes from middle state to final state" => sub {
    my $res = $tester->request([[
      "Mailbox/changes" => {
        sinceState => $middle_state,
        maxChanges => 1,
      },
    ]]);
    ok($res->is_success, "Mailbox/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/changes")->arguments,
      superhashof({
        accountId      => jstr($account->accountId),
        oldState       => jstr($middle_state),
        newState       => jstr($end_state),
        hasMoreChanges => jfalse,
        created        => [ $mailbox2->id ],
        updated        => [],
        destroyed      => [],
      }),
      "Response looks good",
    );
  };

  subtest "final state says no changes" => sub {
    my $res = $tester->request([[
      "Mailbox/changes" => {
        sinceState => $end_state,
        maxChanges => 1,
      },
    ]]);
    ok($res->is_success, "Mailbox/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/changes")->arguments,
      superhashof({
        accountId      => jstr($account->accountId),
        oldState       => jstr($end_state),
        newState       => jstr($end_state),
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [],
        destroyed      => [],
      }),
      "Response looks good",
    );
  };
};
