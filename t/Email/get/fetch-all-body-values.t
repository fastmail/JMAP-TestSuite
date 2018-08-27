use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;

  my $body = "an email body $$";

  my $message = $mbox->add_message({ body => $body });

  subtest "no fetchAllBodyValues supplied" => sub {
    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [ 'bodyStructure', 'bodyValues' ],
      },
    ]]);
    ok($res->is_success, "Email/get")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Email/get")->arguments,
      superhashof({
        accountId => jstr($account->accountId),
        state     => jstr(),
        list      => [{
          id => $message->id,
          bodyValues => {},
          bodyStructure => superhashof({ partId => jstr() }),
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "explicit false fetchAllBodyValues supplied" => sub {
    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [ 'bodyStructure', 'bodyValues' ],
        fetchAllBodyValues => jfalse(),
      },
    ]]);
    ok($res->is_success, "Email/get")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Email/get")->arguments,
      superhashof({
        accountId => jstr($account->accountId),
        state     => jstr(),
        list      => [{
          id => $message->id,
          bodyValues => {},
          bodyStructure => superhashof({ partId => jstr() }),
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "explicit true fetchAllBodyValues supplied" => sub {
    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [ 'bodyStructure', 'bodyValues' ],
        fetchAllBodyValues => jtrue(),
      },
    ]]);
    ok($res->is_success, "Email/get")
      or diag explain $res->http_response->as_string;

    my $arg = $res->single_sentence("Email/get")->arguments;

    my $part_id = $arg->{list}[0]{bodyStructure}{partId};
    ok(defined $part_id, 'we have a part id');

    jcmp_deeply(
      $arg->{list}[0]{bodyValues},
      {
        $part_id => {
          value             => $body,
          isTruncated       => jfalse(),
          isEncodingProblem => jfalse(),
        },
      },
      "bodyValues looks right"
    ) or diag explain $res->as_stripped_triples;
  };
};
