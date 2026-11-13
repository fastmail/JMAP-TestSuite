use jmaptest;

test {
  my ($self) = @_;

  # XXX - Skip if the server under test doesn't support it

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  # Create two message so we should have 3 states (start state,
  # new thread 1 state, new thread 2 state). Then, ask for changes
  # from start state, with a maxChanges set to 1 so we should get
  # hasMoreChanges when sinceState is start state.

  my $start_state = $account->get_state('thread');

  my $message1 = $account->create_mailbox->add_message;

  my $message2 = $account->create_mailbox->add_message;

  my $end_state = $account->get_state('thread');

  my ($middle_state, $first);

  subtest "changes from start state" => sub {
    my $res = $tester->request([[
      "Thread/changes" => {
        sinceState => $start_state,
        maxChanges => 1,
      },
    ]]);
    ok($res->is_success, "Thread/changes")
      or diag explain $res->response_payload;

    # RFC 8620 S5.2: a server unable to split the changes "MUST return a
    # cannotCalculateChanges error".
    my $s = $res->single_sentence;
    if ($s->name eq 'error') {
      is($s->arguments->{type}, 'cannotCalculateChanges', "can't split: cannotCalculateChanges");
      return;
    }

    jcmp_deeply(
      $res->single_sentence("Thread/changes")->arguments,
      {
        accountId      => jstr($account->accountId),
        oldState       => jstr($start_state),
        newState       => all(jstr, none($start_state, $end_state)),
        hasMoreChanges => jtrue,
        created        => [ any($message1->threadId, $message2->threadId) ],
        updated        => [],
        destroyed      => [],
      },
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;

    $middle_state = $res->single_sentence->arguments->{newState};
    $first        = $res->single_sentence->arguments->{created}[0];
    ok($middle_state, 'grabbed middle state');
  };


  subtest "changes from middle state to final state" => sub {
    plan skip_all => "the server could not split the changes" unless defined $middle_state;

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
        created        => [ ($first // q{}) eq $message1->threadId ? $message2->threadId : $message1->threadId ],
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

    my $changes = $res->single_sentence->arguments;

    jcmp_deeply(
      $res->single_sentence("Thread/changes")->arguments,
      {
        accountId      => jstr($account->accountId),
        oldState       => jstr($end_state),
        newState       => jstr,
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [],
        destroyed      => [],
      },
      "Response looks good",
    );

    # RFC 8620 S5.1: servers SHOULD return the same state if nothing changed.
    note("newState differs from oldState though nothing changed (a SHOULD)")
      if ($changes->{newState} // q{}) ne $end_state;
  };
};
