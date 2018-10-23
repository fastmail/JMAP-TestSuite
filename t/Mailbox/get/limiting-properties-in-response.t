use jmaptest;

use JMAP::TestSuite::Util qw(mailbox);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mailbox1 = $account->create_mailbox;

  subtest "properties => null gives us all properties" => sub {
    my $res = $tester->request([[
      "Mailbox/get" => {
        ids        => [ $mailbox1->id ],
        properties => undef,
      },
    ]]);
    ok($res->is_success, "Mailbox/get")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/get")->arguments,
      superhashof({
        accountId => jstr($account->accountId),
        state     => jstr(),
        notFound  => [],
      }),
      "Base response looks good",
    ) or diag explain $res->as_stripped_triples;

    my @found = @{ $res->single_sentence("Mailbox/get")->arguments->{list} };

    is(@found, 1, 'got only 1 mailbox');

    jcmp_deeply(
      $found[0],
      mailbox({
        id            => jstr($mailbox1->id),
        name          => jstr($mailbox1->name),
        isSubscribed  => jfalse,
        isSeenShared  => jfalse,
        totalEmails   => jnum(0),
        unreadEmails  => jnum(0),
        totalThreads  => jnum(0),
        unreadThreads => jnum(0),
      }),
      "Our mailbox looks good"
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "Limiting to a few properties works and includes id" => sub {
    my $res = $tester->request([[
      "Mailbox/get" => {
        ids        => [ $mailbox1->id ],
        properties => [ 'name', 'sortOrder' ],
      },
    ]]);
    ok($res->is_success, "Mailbox/get")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/get")->arguments,
      superhashof({
        accountId => jstr($account->accountId),
        state     => jstr(),
        notFound  => [],
      }),
      "Base response looks good",
    ) or diag explain $res->as_stripped_triples;

    my @found = @{ $res->single_sentence("Mailbox/get")->arguments->{list} };

    is(@found, 1, 'got only 1 mailbox');

    jcmp_deeply(
      $found[0],
      {
        id           => jstr($mailbox1->id),
        name         => jstr($mailbox1->name),
        sortOrder    => jnum(),
      },
      "Our mailbox looks good"
    ) or diag explain $res->as_stripped_triples;
  };
};
