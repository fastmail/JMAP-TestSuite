use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  subtest "Only counts changed, should get updatedProperties" => sub {
    my $mailbox = $account->create_mailbox;

    my $mailbox2 = $account->create_mailbox;

    my $state = $account->get_state('mailbox');

    # Add an email to one of them
    $account->add_message_to_mailboxes($mailbox->id);

    my $res = $tester->request([[
      "Mailbox/changes" => { sinceState => $state, },
    ]]);
    ok($res->is_success, "Mailbox/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/changes")->arguments,
      superhashof({
        accountId      => jstr($account->accountId),
        oldState       => jstr($state),
        newState       => all(jstr, none($state)),
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [ $mailbox->id ],
        destroyed      => [],
        updatedProperties => set(qw(
          totalEmails
          unreadEmails
          totalThreads
          unreadThreads
        )),
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "Counts and other things changed, should not get" => sub {
    my $mailbox = $account->create_mailbox;

    my $state = $account->get_state('mailbox');

    # Add an email to one of them
    $account->add_message_to_mailboxes($mailbox->id);

    # Add a new mailbox
    my $mailbox2 = $account->create_mailbox;

    my $res = $tester->request([[
      "Mailbox/changes" => { sinceState => $state, },
    ]]);
    ok($res->is_success, "Mailbox/changes")
      or diag explain $res->http_response->as_string;

    my $changes = $res->single_sentence("Mailbox/changes")->arguments;

    jcmp_deeply(
      $changes,
      superhashof({
        accountId      => jstr($account->accountId),
        oldState       => jstr($state),
        newState       => all(jstr, none($state)),
        hasMoreChanges => jfalse,
        created        => [ $mailbox2->id, ],
        updated        => [ $mailbox->id, ],
        destroyed      => [],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;

    ok(
         ! exists $changes->{updatedProperties}
      || ! defined $changes->{updatedProperties},
      "updatedProperties is null or omitted"
    );
  };
};
