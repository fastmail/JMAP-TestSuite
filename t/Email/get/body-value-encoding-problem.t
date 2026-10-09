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
    'Subject: encoding problems',
    "Message-ID: $mid",
    'MIME-Version: 1.0',
    'Content-Type: multipart/mixed; boundary="b1"',
    '',
    '--b1',
    'Content-Type: text/plain; charset=utf-8',
    '',
    'good',
    '--b1',
    'Content-Type: text/plain; charset=x-jmts-no-such-charset',
    '',
    'unknown charset',
    '--b1',
    'Content-Type: text/plain; charset=utf-8',
    '',
    "bad \xff\xfe bytes",
    '--b1',
    'Content-Type: text/plain; charset=utf-8',
    'Content-Transfer-Encoding: x-jmts-no-such-encoding',
    '',
    'unknown encoding',
    '--b1--',
    '';

  my $message = $account->create_mailbox->add_message({
    email_type  => 'provided',
    email       => $email,
    dont_modify => 1,
  });

  my $res = $tester->request([[
    "Email/get" => {
      ids                => [ $message->id ],
      properties         => [ 'bodyStructure', 'bodyValues' ],
      bodyProperties     => [ 'partId', 'subParts' ],
      fetchAllBodyValues => jtrue(),
    },
  ]]);
  ok($res->is_success, "Email/get")
    or diag explain $res->response_payload;

  my $got = $res->single_sentence("Email/get")->arguments->{list}[0];
  my @ids = map {; $_->{partId} } @{ $got->{bodyStructure}{subParts} || [] };
  is(@ids, 4, "four leaf parts") or return diag explain $got;

  # RFC 8621 S4.1.4: isEncodingProblem "is true if malformed sections were
  # found while decoding the charset, the charset was unknown, or the
  # content-transfer-encoding was unknown".
  my %want = (
    good               => jfalse(),
    'unknown charset'  => jtrue(),
    'invalid UTF-8'    => jtrue(),
    'unknown encoding' => jtrue(),
  );
  my @labels = ('good', 'unknown charset', 'invalid UTF-8', 'unknown encoding');

  for my $i (0 .. $#labels) {
    jcmp_deeply(
      $got->{bodyValues}{ $ids[$i] // '' },
      superhashof({
        value             => jstr(),
        isEncodingProblem => $want{ $labels[$i] },
      }),
      "isEncodingProblem for the $labels[$i] part",
    ) or diag explain $got->{bodyValues};
  }
};
