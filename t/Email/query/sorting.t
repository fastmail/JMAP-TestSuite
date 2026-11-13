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

  my $mailbox = $account->create_mailbox;

  # Creation order is the reverse of receivedAt order.
  my $flagged   = $mailbox->add_message({
    subject    => 'flagged',
    receivedAt => '2020-01-02T00:00:00Z',
    keywords   => { '$flagged' => jtrue() },
  });
  my $unflagged = $mailbox->add_message({
    subject    => 'unflagged',
    receivedAt => '2020-01-01T00:00:00Z',
    keywords   => {},
  });

  my $query = sub {
    my ($sort) = @_;

    my $res = $tester->request([[
      "Email/query" => {
        filter => { inMailbox => $mailbox->id },
        sort   => [ $sort ],
      },
    ]]);
    ok($res->is_success, "Email/query") or diag explain $res->response_payload;

    return $res->sentence(0);
  };

  for my $test (
    [ JSON::true,  'ascending puts unflagged first', [ $unflagged->id, $flagged->id ] ],
    [ JSON::false, 'descending puts flagged first',  [ $flagged->id, $unflagged->id ] ],
  ) {
    my ($asc, $name, $want) = @$test;

    subtest "sort by hasKeyword $name" => sub {
      my $sentence = $query->({
        property    => 'hasKeyword',
        keyword     => '$flagged',
        isAscending => $asc,
      });

      # RFC 8621 S4.4.2: hasKeyword is one of the sorts that SHOULD be supported.
      if ($sentence->name eq 'error') {
        is($sentence->arguments->{type}, 'unsupportedSort', 'unsupportedSort')
          or diag explain $sentence->arguments;
        return;
      }

      jcmp_deeply(
        $sentence->arguments->{ids},
        [ map {; jstr($_) } @$want ],
        "ids in hasKeyword order",
      ) or diag explain $sentence->arguments;
    };
  }

  subtest "sort by receivedAt" => sub {
    my $sentence = $query->({
      property    => 'receivedAt',
      isAscending => JSON::true,
    });

    is($sentence->name, 'Email/query', 'got Email/query response')
      or diag explain $sentence->arguments;

    jcmp_deeply(
      $sentence->arguments->{ids},
      [ jstr($unflagged->id), jstr($flagged->id) ],
      "ids in receivedAt order",
    ) or diag explain $sentence->arguments;
  };
};
