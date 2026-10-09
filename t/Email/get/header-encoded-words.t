use jmaptest;
use utf8;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $message = $account->create_mailbox->add_message({
    raw_headers => [
      'From'    => '=?UTF-8?Q?J=C3=B6hn_Smith?= <john@example.net>',
      'To'      => '"Plain" <plain@example.net>, =?UTF-8?Q?Ann_=C3=85?= <ann@example.net>',
      'X-Group' => '=?UTF-8?B?R3LDvHBwZQ==?=: =?UTF-8?Q?Ann_=C3=85?= <ann@example.net>;',
    ],
  });

  my $res = $tester->request([[
    "Email/get" => {
      ids        => [ $message->id ],
      properties => [ qw(
        id
        from
        header:To:asAddresses
        header:X-Group:asGroupedAddresses
      ) ],
    },
  ]]);
  ok($res->is_success, "Email/get")
    or diag explain $res->response_payload;

  # RFC 8621 S4.1.2.3 and S4.1.2.4: "Any syntactically correct encoded
  # sections [RFC2047] with a known encoding MUST be decoded".
  jcmp_deeply(
    $res->single_sentence("Email/get")->arguments->{list},
    [{
      id   => $message->id,
      from => [ { name => 'Jöhn Smith', email => 'john@example.net' } ],
      'header:To:asAddresses' => [
        { name => 'Plain', email => 'plain@example.net' },
        { name => 'Ann Å',  email => 'ann@example.net' },
      ],
      'header:X-Group:asGroupedAddresses' => [{
        name      => 'Grüppe',
        addresses => [ { name => 'Ann Å', email => 'ann@example.net' } ],
      }],
    }],
    "encoded-word display names are decoded",
  ) or diag explain $res->as_stripped_triples;
};
