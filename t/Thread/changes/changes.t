use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  subtest "created entities show up in created" => sub {
    my $state = $account->get_state('thread');

    my $message = $account->create_mailbox->add_message;

    my $res = $tester->request([[
      "Thread/changes" => { sinceState => $state, },
    ]]);
    ok($res->is_success, "Thread/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Thread/changes")->arguments,
      {
        accountId      => jstr($account->accountId),
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [ $message->threadId ],
        updated        => [],
        destroyed      => [],
      },
      "Response looks good",
    );
  };

  subtest "updated entities show up in updated" => sub {
    my $message = $account->create_mailbox->add_message;

    my $state = $account->get_state('thread');

    $message->reply;

    my $res = $tester->request([[
      "Thread/changes" => { sinceState => $state, },
    ]]);
    ok($res->is_success, "Thread/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Thread/changes")->arguments,
      {
        accountId      => jstr($account->accountId),
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [ $message->threadId ],
        destroyed      => [],
      },
      "Response looks good",
    );
  };

  subtest "destroyed entities show up in destroyed" => sub {
    my $message = $account->create_mailbox->add_message;

    my $state = $account->get_state('thread');

    $message->destroy;

    my $res = $tester->request([[
        "Thread/changes" => { sinceState => $state, },
    ]]);
    ok($res->is_success, "Thread/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Thread/changes")->arguments,
      {
        accountId      => jstr($account->accountId),
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [],
        destroyed      => [ $message->threadId ],
      },
      "Response looks good",
    );
  };
};
