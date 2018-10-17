use jmaptest;
use utf8;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;

  my $from    = "test$$\@example.net";
  my $to      = "recip$$\@example.net";
  my $subject = "A subject for $$";
  my $date    = 'Mon, 18 Jun 2018 16:51:28 -0400';
  my $ls      = 'https://example.net';

  my $message = $mbox->add_message({
    from    => $from,
    to      => $to,
    subject => $subject,
    headers => [
      'List-Subscribe' => $ls,
      Date             => $date,
      Single           => 'A single value',
      Multiple         => '1st value',
      Multiple         => '2nd value',
      Multiple         => '3rd value',
    ],
  });

  my $em_msg_id = $message->messageId->[0];

  subtest "No as: prefix - default header-form Raw" => sub {
    # Let's test a few that have different parsed forms
    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [qw(
          header:DAte
          header:Message-Id
          header:FROm
          header:SuBject
          header:List-Subscribe
          header:None
          header:Multiple
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
          id                      => $message->id,
          'header:DAte'           => " $date",
          'header:Message-Id'     => re(qr/^\s<[^>]+>$/),
          'header:FROm' =>        => " $from",
          'header:SuBject'        => " $subject",
          'header:List-Subscribe' => " $ls",
          'header:None'           => undef,
          'header:Multiple'       => ' 3rd value',
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest ":all prefix, single, multi, and none" => sub {
    # Let's test a few that have different parsed forms
    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [qw(
          header:SinglE:all
          header:Multiple:all
          header:None:all
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
          id                      => $message->id,
          'header:SinglE:all'   => [ ' A single value' ],
          'header:Multiple:all' => [
            ' 1st value',
            ' 2nd value',
            ' 3rd value',
          ],
          'header:None:all'     => [],
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "suffix order must be :as{foo}:all" => sub {
    # Let's test a few that have different parsed forms
    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [qw(
          header:None:all:asRaw
        )],
      },
    ]]);
    ok($res->is_success, "Email/get")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("error")->arguments,
      superhashof({
        type => 'invalidArguments',
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "asText" => sub {
    my $message = $mbox->add_message({
      headers => [
        # Make sure these all asText properly
        subject   => "☃",
        comment   => "☃☃",
        'list-id' => "☃☃☃",
        'X-Foo'   => "☃☃☃☃",

        # NFC check on utf8. ANGSTROM SIGN NFCd should become
        # LATIN CAPITAL LETTER A WITH RING ABOVE
        'X-NFC'   => "\N{ANGSTROM SIGN}",
      ],
      raw_headers => [
        'X-Fold'  => " " . ("a" x 50) . " " . ("b" x 50),
      ]
    });

    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [qw(
          header:subject:asRaw
          header:comment:asRaw
          header:list-id:asRaw
          header:x-foo:asRaw
          header:x-nfc:asRaw
          header:x-fold:asRaw
          header:subject:asText
          header:comment:asText
          header:list-id:asText
          header:x-foo:asText
          header:x-nfc:asText
          header:x-fold:asText
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
          id                      => $message->id,
          'header:subject:asRaw'  => " =?UTF-8?B?4piD?=",
          'header:comment:asRaw'  => " =?UTF-8?B?4piD4piD?=",
          'header:list-id:asRaw'  => " =?UTF-8?B?4piD4piD4piD?=",
          'header:x-foo:asRaw'    => " =?UTF-8?B?4piD4piD4piD4piD?=",
          'header:x-nfc:asRaw'    => " =?UTF-8?B?4oSr?=",
          'header:x-fold:asRaw'   => "  " . ("a" x 50) . "\r\n " . ("b" x 50),
          'header:subject:asText' => "☃",
          'header:comment:asText' => "☃☃",
          'header:list-id:asText' => "☃☃☃",
          'header:x-foo:asText'   => "☃☃☃☃",
          'header:x-nfc:asText'   => "\N{LATIN CAPITAL LETTER A WITH RING ABOVE}",
          'header:x-fold:asText'  => ("a" x 50) . " " . ("b" x 50),
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "asAddresses" => sub {
    my $name = "Foo \\S";
    my $email = "foos$$\@example.net";

    my $value = qq{"$name" <$email>};

    my $expect_name = $name;

    # \S -> S (quoted-pair)
    $expect_name =~ s/\\//g;

    # No name
    my $from_value = 'foo@example.net';

    my @hlist = qw(
      Sender
      Reply-To
      Cc
      Bcc
      Resent-From
      Resent-Sender
      Resent-Reply-To
      Resent-To
      Resent-Cc
      X-Foo
      To
    );

    my $long_name = "a" x 58;
    my $long_email = 'foo@example.net';

    my $long_value = qq{"$long_name" <$long_email>};

    my $group_value = 'A group: foo <foo@example.org>,"bar d" <bar@example.org>;';

    my $message = $mbox->add_message({
      raw_headers => [
        ( map {;
          $_ => $value,
        } @hlist, ),
        'Resent-Bcc' => $long_value,
        From      => $from_value,
      ],
      headers => [
        'X-Group' => $group_value,
      ],
    });

    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [
          ( map {;
            "header:$_:asRaw",
          } @hlist, ),
          ( map {;
            "header:$_:asAddresses",
          } @hlist, ),
          qw(
            header:From:asRaw
            header:From:asAddresses
            header:Resent-Bcc:asRaw
            header:Resent-Bcc:asAddresses
            header:X-Group:asRaw
            header:X-Group:asAddresses
          ),
        ],
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
          id                      => $message->id,
          ( map {;
            "header:$_:asRaw" => " $value",
          } @hlist, ),
          ( map {;
            "header:$_:asAddresses" => [{
              name  => $expect_name,
              email => $email,
            }],
          } @hlist, ),
          'header:From:asRaw' => " $from_value",
          'header:From:asAddresses' => [{
            name => undef,
            email => $from_value,
          }],
          'header:To:asAddresses' => [{
            name => $expect_name,
            email => $email,
          }],
          'header:Resent-Bcc:asRaw' => qq{ "$long_name"\r\n <$long_email>},
          'header:Resent-Bcc:asAddresses' => [{
            name  => $long_name,
            email => $long_email,
          }],
          'header:X-Group:asRaw' => " $group_value",
          'header:X-Group:asAddresses' => [
            {
              name  => 'A group',
              email => undef,
            }, {
              name  => 'foo',
              email => 'foo@example.org',
            }, {
              name  => 'bar d',
              email => 'bar@example.org',
            }, {
              name => undef,
              email => undef,
            },
          ],
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "asMessageIds" => sub {
    my @hlist = qw(
      Message-ID
      In-Reply-To
      Resent-Message-ID
      X-Foo
    );

    my $mid1 = 'foo@example.com';
    my $value = "<$mid1>";

    my $mid2 = ('f' x 45) . '@example.com';
    my $mid3 = 'bar@example.com';

    my $long_value = "<$mid2> <$mid3>";

    my $message = $mbox->add_message({
      headers => [
        ( map {;
          $_ => $value,
        } @hlist, ),
        References => $long_value,
      ],
    });

    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [
          ( map {;
            "header:$_:asRaw",
          } @hlist, ),
          ( map {;
            "header:$_:asMessageIds",
          } @hlist, ),
          qw(
            header:References:asRaw
            header:References:asMessageIds
          ),
        ],
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
          id                      => $message->id,
          ( map {;
            "header:$_:asRaw" => " $value",
          } @hlist, ),
          ( map {;
            "header:$_:asMessageIds" => [ $mid1 ],
          } @hlist, ),
          'header:References:asRaw' => " <$mid2>\r\n <$mid3>",
          'header:References:asMessageIds' => [ $mid2, $mid3 ],
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "asDate" => sub {
    my @hlist = qw(
      Date
      Resent-Date
      X-Foo
    );

    my $value = "Thu, 13 Feb 1969 23:32 -0330 (Newfoundland Time)";

    # 13th at 23:32 + 3.5h...
    my $expect = "1969-02-14T03:02:00Z";

    my $message = $mbox->add_message({
      raw_headers => [
        ( map {;
          $_ => $value,
        } @hlist, ),
        'X-Broken' => 'not a date',
      ],
    });

    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [
          ( map {;
            "header:$_:asRaw",
          } @hlist, ),
          ( map {;
            "header:$_:asDate",
          } @hlist, ),
          qw(
            header:X-Broken:asRaw
            header:X-Broken:asDate
          ),
        ],
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
          id                          => $message->id,
          ( map {;
            "header:$_:asRaw" => " $value",
          } @hlist, ),
          ( map {;
            "header:$_:asDate" => "$expect",
          } @hlist, ),
          'header:X-Broken:asRaw' => " not a date",
          'header:X-Broken:asDate' => undef,
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "asURLs" => sub {
    my @hlist = qw(
      List-Help
      List-Unsubscribe
      List-Subscribe
      List-Post
      List-Owner
      List-Archive
      X-Foo
    );

    my $url1 = "http://example.net";
    my $url2 = "http://example.org/" . ("a" x 35);

    my $value = "<$url1> <$url2>";

    my $message = $mbox->add_message({
      raw_headers => [
        ( map {;
          $_ => $value,
        } @hlist, ),
        'X-Broken' => 'not a url',
      ],
    });

    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [
          ( map {;
            "header:$_:asRaw",
          } @hlist, ),
          ( map {;
            "header:$_:asURLs",
          } @hlist, ),
          qw(
            header:X-Broken:asRaw
            header:X-Broken:asURLs
          ),
        ],
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
          ( map {;
            "header:$_:asRaw" => " <$url1>\r\n <$url2>",
          } @hlist, ),
          ( map {;
            "header:$_:asURLs" => [ $url1, $url2 ],
          } @hlist, ),
          'header:X-Broken:asRaw' => " not a url",
          'header:X-Broken:asURLs' => undef,
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };
};
