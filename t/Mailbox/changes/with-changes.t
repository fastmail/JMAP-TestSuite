use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  subtest "created entities show up in created" => sub {
    my $state = $account->get_state('mailbox');

    my $mailbox = $account->create_mailbox;

    my $res = $tester->request([[
      "Mailbox/changes" => { sinceState => $state, },
    ]]);
    ok($res->is_success, "Mailbox/changes")
      or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("Mailbox/changes")->arguments,
      superhashof({
        accountId      => jstr($account->accountId),
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [ $mailbox->id ],
        updated        => [],
        destroyed      => [],
      }),
      "Response looks good",
    );
  };

  subtest "updated entities show up in updated" => sub {
    my $mailbox = $account->create_mailbox;

    my $state = $account->get_state('mailbox');

    subtest "update the mailbox" => sub {
      my $res = $tester->request([[
        "Mailbox/set" => {
          update => {
            $mailbox->id => { name => "An updated mailbox $^T - $$" },
          },
        },
      ]]);
      ok($res->is_success, "Mailbox/set")
        or diag explain $res->response_payload;
    };

    my $res = $tester->request([[
      "Mailbox/changes" => { sinceState => $state, },
    ]]);
    ok($res->is_success, "Mailbox/changes")
      or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("Mailbox/changes")->arguments,
      superhashof({
        accountId      => jstr($account->accountId),
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [ $mailbox->id ],
        destroyed      => [],
      }),
      "Response looks good",
    );
  };

  subtest "destroyed entities show up in destroyed" => sub {
    my $mailbox = $account->create_mailbox;

    my $state = $account->get_state('mailbox');

    subtest "destroy the mailbox" => sub {
      my $res = $tester->request([[
        "Mailbox/set" => {
          destroy => [ $mailbox->id ],
        },
      ]]);
      ok($res->is_success, "Mailbox/set")
        or diag explain $res->response_payload;
    };

    my $res = $tester->request([[
      "Mailbox/changes" => { sinceState => $state, },
    ]]);
    ok($res->is_success, "Mailbox/changes")
      or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("Mailbox/changes")->arguments,
      superhashof({
        accountId      => jstr($account->accountId),
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [],
        destroyed      => [ $mailbox->id ],
      }),
      "Response looks good",
    );
  };
};
