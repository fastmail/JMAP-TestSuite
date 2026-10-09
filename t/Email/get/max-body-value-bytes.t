use jmaptest;
use utf8;

use Encode ();

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mbox = $account->create_mailbox;

  my $body = "1234☃"; # snowman is 3 bytes (E2 98 83)

  my $message = $mbox->add_message({
    attributes => {
      content_type => 'text/plain',
      charset      => 'UTF-8',
      encoding     => 'quoted-printable',
    },
    body_str => $body,
  });

  # RFC 8621 S4.2: a truncated value "does not exceed this number of octets"
  # and is valid UTF-8; any such prefix of the body is acceptable.
  my $truncated_to = sub {
    my ($max) = @_;
    return superhashof({
      value => code(sub {
        my ($got) = @_;
        return (0, "value is not a prefix of the body")
          unless defined $got && index($body, $got) == 0;
        return (0, "value exceeds $max octets")
          if length(Encode::encode('UTF-8', $got)) > $max;
        return 1;
      }),
      isTruncated => jtrue(),
    });
  };

  subtest "invalid values" => sub {
    for my $invalid (-5, "cat", "1", {}, [], jtrue, undef) {
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
          "error" => superhashof({
            type => 'invalidArguments',
          }),
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

  subtest "zero means no truncation" => sub {
    my $res = $tester->request([[
      "Email/get" => {
        ids                => [ $message->id ],
        properties         => [ 'bodyStructure', 'bodyValues' ],
        fetchAllBodyValues => jtrue(),
        maxBodyValueBytes  => 0,
      },
    ]]);
    ok($res->is_success, "Email/get")
      or diag explain $res->response_payload;

    my $arg = $res->single_sentence("Email/get")->arguments;

    my $part_id = $arg->{list}[0]{bodyStructure}{partId};
    ok(defined $part_id, 'we have a part id');

    # RFC 8621 S4.2: maxBodyValueBytes "If 0 (the default), no truncation
    # occurs."
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
      $truncated_to->(3),
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

      jcmp_deeply(
        $arg->{list}[0]{bodyValues}{$part_id},
        $truncated_to->($mid_snowman),
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
