use jmaptest;

test {
  my ($self) = @_;

  # XXX - Skip if the server under test doesn't support it

  my $account = $self->any_account;
  my $tester  = $account->tester;

  # Create two message so we should have 3 states (start state,
  # new thread 1 state, new thread 2 state). Then, ask for changes
  # from start state, with a maxChanges set to 1 so we should get
  # hasMoreChanges when sinceState is start state.

  my $start_state = $account->get_state('thread');

  my $message1 = $account->create_mailbox->add_message;

  my $message2 = $account->create_mailbox->add_message;

  my $end_state = $account->get_state('thread');

  my $middle_state;

  subtest "changes from start state" => sub {
    my $res = $tester->request([[
      "Thread/changes" => {
        sinceState => $start_state,
        maxChanges => 1,
      },
    ]]);
    ok($res->is_success, "Thread/changes")
      or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("Thread/changes")->arguments,
      {
        accountId      => jstr($account->accountId),
        oldState       => jstr($start_state),
        newState       => all(jstr, none($start_state, $end_state)),
        hasMoreChanges => jtrue,
        created        => [ $message1->threadId ],
        updated        => [],
        destroyed      => [],
      },
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;

    $middle_state = $res->single_sentence->arguments->{newState};
    ok($middle_state, 'grabbed middle state');
  };


  subtest "changes from middle state to final state" => sub {
    my $res = $tester->request([[
      "Thread/changes" => {
        sinceState => $middle_state,
        maxChanges => 1,
      },
    ]]);
    ok($res->is_success, "Thread/changes")
      or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("Thread/changes")->arguments,
      {
        accountId      => jstr($account->accountId),
        oldState       => jstr($middle_state),
        newState       => jstr($end_state),
        hasMoreChanges => jfalse,
        created        => [ $message2->threadId ],
        updated        => [],
        destroyed      => [],
      },
      "Response looks good",
    );
  };

  subtest "final state says no changes" => sub {
    my $res = $tester->request([[
      "Thread/changes" => {
        sinceState => $end_state,
        maxChanges => 1,
      },
    ]]);
    ok($res->is_success, "Thread/changes")
      or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("Thread/changes")->arguments,
      {
        accountId      => jstr($account->accountId),
        oldState       => jstr($end_state),
        newState       => jstr($end_state),
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [],
        destroyed      => [],
      },
      "Response looks good",
    );
  };
};
