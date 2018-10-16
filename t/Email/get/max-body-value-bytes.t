use jmaptest;
use utf8;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;

  my $body = "1234☃"; # snowman is 3 bytes (E2 98 83)

  my $message = $mbox->add_message({
    attributes => {
      content_type => 'text/plain',
      charset      => 'utf8',
      encoding     => 'quoted-printable',
    },
    body_str => $body,
  });

  subtest "invalid values" => sub {
    for my $invalid (-5, 0, "cat", "1", {}, [], jtrue, undef) {
      my $desc = defined $invalid && ! ref $invalid ? $invalid
               : defined $invalid                   ? ref $invalid
               :                                      '<undef>';

      my $res = $tester->request_ok(
        [[
          "Email/get" => {
            ids               => [ $message->id ],
            properties        => [ 'bodyStructure', 'bodyValues' ],
            maxBodyValueBytes => $invalid,
          },
        ]],
        [[
          "error" => {
            type => 'invalidArguments',
            arguments => [ 'maxBodyValueBytes' ], # XXX - not to spec
          },
        ]],
        "invalid value '$desc'"
      );
    }
  };

  subtest "truncate is higher than actual number of bytes" => sub {
    my $res = $tester->request([[
      "Email/get" => {
        ids                => [ $message->id ],
        properties         => [ 'bodyStructure', 'bodyValues' ],
        fetchAllBodyValues => jtrue(),
        maxBodyValueBytes  => 500,
      },
    ]]);
    ok($res->is_success, "Email/get")
      or diag explain $res->response_payload;

    my $arg = $res->single_sentence("Email/get")->arguments;

    my $part_id = $arg->{list}[0]{bodyStructure}{partId};
    ok(defined $part_id, 'we have a part id');

    jcmp_deeply(
      $arg->{list}[0]{bodyValues}{$part_id},
      superhashof({
        value => $body,
        isTruncated => jfalse(),
      }),
      'body value not truncated',
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "truncate between single-byte characters" => sub {
    my $res = $tester->request([[
      "Email/get" => {
        ids                => [ $message->id ],
        properties         => [ 'bodyStructure', 'bodyValues' ],
        fetchAllBodyValues => jtrue(),
        maxBodyValueBytes  => 3,
      },
    ]]);
    ok($res->is_success, "Email/get")
      or diag explain $res->response_payload;

    my $arg = $res->single_sentence("Email/get")->arguments;

    my $part_id = $arg->{list}[0]{bodyStructure}{partId};
    ok(defined $part_id, 'we have a part id');

    jcmp_deeply(
      $arg->{list}[0]{bodyValues}{$part_id},
      superhashof({
        value => '123',
        isTruncated => jtrue(),
      }),
      'body value truncated correctly',
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "truncate does not break UTF-8" => sub {
    for my $mid_snowman (5, 6) {
      my $res = $tester->request([[
        "Email/get" => {
          ids                => [ $message->id ],
          properties         => [ 'bodyStructure', 'bodyValues' ],
          fetchAllBodyValues => jtrue(),
          maxBodyValueBytes  => $mid_snowman,
        },
      ]]);
      ok($res->is_success, "Email/get")
        or diag explain $res->response_payload;

      my $arg = $res->single_sentence("Email/get")->arguments;

      my $part_id = $arg->{list}[0]{bodyStructure}{partId};
      ok(defined $part_id, 'we have a part id');

      # Since we're asking for < 7 bytes and the snowman accounts for
      # bytes 5 and 6, and 7, the server MUST NOT EXCEED our request and so
      # must return everything before the snowman but not include it.
      jcmp_deeply(
        $arg->{list}[0]{bodyValues}{$part_id},
        superhashof({
          value => '1234',
          isTruncated => jtrue(),
        }),
        'body value truncated correctly',
      ) or diag explain $res->as_stripped_triples;
    }
  };

  subtest "request at boundary of email/utf8 gives us all data" => sub {
    my $res = $tester->request([[
      "Email/get" => {
        ids                => [ $message->id ],
        properties         => [ 'bodyStructure', 'bodyValues' ],
        fetchAllBodyValues => jtrue(),
        maxBodyValueBytes  => 7,
      },
    ]]);
    ok($res->is_success, "Email/get")
      or diag explain $res->response_payload;

    my $arg = $res->single_sentence("Email/get")->arguments;

    my $part_id = $arg->{list}[0]{bodyStructure}{partId};
    ok(defined $part_id, 'we have a part id');

    jcmp_deeply(
      $arg->{list}[0]{bodyValues}{$part_id},
      superhashof({
        value => $body,
        isTruncated => jfalse(),
      }),
      'body value not truncated with exact match length of bytes',
    ) or diag explain $res->as_stripped_triples;
  };
};
