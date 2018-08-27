use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;

  my $from    = "test$$\@example.net";
  my $to      = "recip$$\@example.net";
  my $subject = "A subject for $$";

  my $message = $mbox->add_message({
    from    => $from,
    to      => $to,
    subject => $subject,
  });

  $tester->request_ok(
    [[
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [ 'textBody' ],
      },
    ]],
    [[
      superhashof({
        accountId => jstr($account->accountId),
        state     => jstr(),
        list      => [{
          id => $message->id,
          textBody => [{
            partId      => jstr(),
            blobId      => jstr(),
            size        => jnum(),
            name        => undef,
            type        => 'text/plain',
            charset     => 'us-ascii', # XXX ? Legit? -- alh, 2018-06-14
            disposition => undef,
            cid         => undef,
            language    => any([], undef),
            location    => undef,
          }],
        }],
      }),
    ]],
    "no bodyProperties specified, defaults returned",
  );

  subtest "limit to no body properties" => sub {
    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [ 'textBody' ],
        bodyProperties => [],
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
          textBody => [{}],
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "limit to all body properties" => sub {
    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [ 'textBody' ],
        bodyProperties => [qw(
          partId blobId size headers name type charset disposition
          cid language location subParts
        )],
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
          textBody => [{
            partId      => jstr(),
            blobId      => jstr(),
            size        => jnum(),
            name        => undef,
            type        => 'text/plain',
            charset     => 'us-ascii', # XXX ? Legit? -- alh, 2018-06-14
            disposition => undef,
            cid         => undef,
            language    => any([], undef),
            location    => undef,
            subParts    => [],
            headers     => [
              {
                name  => 'From',
                value => re(qr/\Q$from\E/),
              }, {
                name  => 'To',
                value => re(qr/\Q$to\E/),
              }, {
                name  => 'Subject',
                value => re(qr/\Q$subject\E/),
              }, {
                name  => 'Message-Id',
                value => re(qr/<.*>/),
              }, {
                name  => 'Date',
                value => re(qr/\w/),
              }, {
                name  => 'MIME-Version',
                value => re(qr/1\.0/),
              },
            ],
          }],
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "limit to some body properties" => sub {
    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [ 'textBody' ],
        bodyProperties => [qw(
          size name type
        )],
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
          textBody => [{
            size        => jnum(),
            name        => undef,
            type        => 'text/plain',
          }],
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };
};
