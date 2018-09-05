use jmaptest;

use JMAP::TestSuite::Util qw(mailbox);

# Can't have existing data so must be pristine
attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mailbox1 = $account->create_mailbox;

  my $mailbox2 = $account->create_mailbox;

  # Standard /get method. The ids argument may be null to fetch all at once.

  for my $test (
    [ "No arguments" => {}, ],
    [ "null ids"     => { ids => undef }, ],
  ) {
    my ($name, $args) = @$test;

    subtest "$name" => sub {
      my $res = $tester->request([[
        "Mailbox/get" => $args,
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
      );

      my @found = grep {;
        $_->{id} eq $mailbox1->id
      } @{ $res->single_sentence("Mailbox/get")->arguments->{list} };

      is(@found, 1, 'found our mailbox');

      jcmp_deeply(
        $found[0],
        mailbox({
          id            => jstr($mailbox1->id),
          name          => jstr($mailbox1->name),
          isSubscribed  => jfalse,
          totalEmails   => jnum(0),
          unreadEmails  => jnum(0),
          totalThreads  => jnum(0),
          unreadThreads => jnum(0),
        }),
        "Our mailbox looks good"
      ) or diag explain $res->as_stripped_triples;
    };
  }

  subtest "Limit by id" => sub {
    my $res = $tester->request([[
      "Mailbox/get" => { ids => [ $mailbox1->id ], },
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
        totalEmails   => jnum(0),
        unreadEmails  => jnum(0),
        totalThreads  => jnum(0),
        unreadThreads => jnum(0),
      }),
      "Our mailbox looks good"
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "Limit to no ids" => sub {
    my $res = $tester->request([[
      "Mailbox/get" => { ids => [ ], },
    ]]);
    ok($res->is_success, "Mailbox/get")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/get")->arguments,
      superhashof({
        accountId => jstr($account->accountId),
        state     => jstr(),
        list      => [],
        notFound  => [],
      }),
      "Base response looks good, has no mailboxes",
    ) or diag explain $res->as_stripped_triples;
  };
};
