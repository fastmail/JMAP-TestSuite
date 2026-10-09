use jmaptest;

use Email::MessageID;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mid = Email::MessageID->new->in_brackets;

  my $email = join "\r\n",
    'From: a@example.net',
    'To: b@example.net',
    'Subject: part headers',
    "Message-ID: $mid",
    'MIME-Version: 1.0',
    'Content-Type: multipart/mixed; boundary="b1"',
    '',
    '--b1',
    'Content-Type: text/plain; charset=us-ascii',
    'X-Part: =?UTF-8?Q?first_=C3=A9?=',
    'X-Multi: one',
    'X-Multi: two',
    '',
    'first body',
    '--b1',
    'Content-Type: text/plain; charset=us-ascii',
    '',
    'second body',
    '--b1--',
    '';

  my $message = $account->create_mailbox->add_message({
    email_type  => 'provided',
    email       => $email,
    dont_modify => 1,
  });

  my $res = $tester->request([[
    "Email/get" => {
      ids            => [ $message->id ],
      properties     => [ 'bodyStructure' ],
      bodyProperties => [ qw(
        subParts
        header:Content-Type
        header:x-part:asText
        header:X-Multi:all
        header:X-None
      ) ],
    },
  ]]);
  ok($res->is_success, "Email/get")
    or diag explain $res->response_payload;

  # Whether a leaf part's subParts is null, empty or left out is not what
  # this test is about.
  my $leaf = sub {
    my (%part) = @_;
    return any(\%part, { %part, subParts => any(undef, []) });
  };

  # RFC 8621 S4.1.4: EmailBodyPart properties may be "individual header
  # fields, following the same syntax and semantics as for the Email object".
  jcmp_deeply(
    $res->single_sentence("Email/get")->arguments->{list},
    [{
      id            => $message->id,
      bodyStructure => {
        'header:Content-Type'  => ' multipart/mixed; boundary="b1"',
        'header:x-part:asText' => undef,
        'header:X-Multi:all'   => [],
        'header:X-None'        => undef,
        subParts               => [
          $leaf->(
            'header:Content-Type'  => ' text/plain; charset=us-ascii',
            'header:x-part:asText' => "first \x{e9}",
            'header:X-Multi:all'   => [ ' one', ' two' ],
            'header:X-None'        => undef,
          ),
          $leaf->(
            'header:Content-Type'  => ' text/plain; charset=us-ascii',
            'header:x-part:asText' => undef,
            'header:X-Multi:all'   => [],
            'header:X-None'        => undef,
          ),
        ],
      },
    }],
    "body parts carry the requested header properties",
  ) or diag explain $res->as_stripped_triples;
};
