use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  subtest "created entities show up in created" => sub {
    my $state = $account->get_state('email');

    my $message = $account->create_mailbox->add_message;

    my $res = $tester->request([[
      "Email/changes" => { sinceState => $state, },
    ]]);
    ok($res->is_success, "Email/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Email/changes")->arguments,
      {
        accountId      => jstr($account->accountId),
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [ $message->id ],
        updated        => [],
        destroyed      => [],
      },
      "Response looks good",
    );
  };

  subtest "updated entities show up in updated" => sub {
    my $message = $account->create_mailbox->add_message;

    my $state = $account->get_state('email');

    $message->update({ keywords => { foo => JSON::true } });

    my $res = $tester->request([[
      "Email/changes" => { sinceState => $state, },
    ]]);
    ok($res->is_success, "Email/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Email/changes")->arguments,
      {
        accountId      => jstr($account->accountId),
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [ $message->id ],
        destroyed      => [],
      },
      "Response looks good",
    );
  };

  subtest "destroyed entities show up in destroyed" => sub {
    my $message = $account->create_mailbox->add_message;

    my $state = $account->get_state('email');

    $message->destroy;

    my $res = $tester->request([[
      "Email/changes" => { sinceState => $state, },
    ]]);
    ok($res->is_success, "Email/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Email/changes")->arguments,
      {
        accountId      => jstr($account->accountId),
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [],
        destroyed      => [ $message->id ],
      },
      "Response looks good",
    );
  };
};
