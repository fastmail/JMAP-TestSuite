use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mbox    = $account->create_mailbox;
  my $message = $mbox->add_message({ subject => "invalid keywords $$" });

  # RFC 8621 S4.1.1: a keyword is "a case-insensitive string of 1-255
  # characters in the ASCII subset %x21-%x7e" that "MUST NOT include" any of
  # ( ) { ] % * " \ and "The value for each key in the object MUST be true."
  my @bad = (
    (map {; [ "keyword containing '$_'" => { "a${_}b" => jtrue } ] }
      '(', ')', '{', ']', '%', '*', '"', '\\', ' '),
    [ "empty keyword"            => { ''        => jtrue } ],
    [ "256-character keyword"    => { 'k' x 256 => jtrue } ],
    [ "non-ASCII keyword"        => { "caf\x{e9}" => jtrue } ],
    [ "keyword with value false" => { 'valid'   => jfalse } ],
  );

  for my $case (@bad) {
    my ($desc, $keywords) = @$case;

    subtest $desc => sub {
      my $res = $tester->request([[
        "Email/set" => {
          create => {
            new => {
              mailboxIds => { $mbox->id => jtrue },
              keywords   => $keywords,
              subject    => "invalid keywords create $$",
            },
          },
          update => {
            $message->id => { keywords => $keywords },
          },
        },
      ]]);

      my $args = $res->single_sentence('Email/set')->arguments;
      jcmp_deeply(
        $args->{notCreated},
        { new => invalid_properties('keywords') },
        "create is rejected",
      ) or diag explain $res->as_stripped_triples;
      jcmp_deeply(
        $args->{notUpdated},
        { $message->id => invalid_properties('keywords') },
        "update is rejected",
      ) or diag explain $res->as_stripped_triples;

      $tester->request_ok(
        [ "Email/get" => { ids => [ $message->id ], properties => [ 'keywords' ] } ],
        superhashof({ list => [ { id => $message->id, keywords => {} } ] }),
        "the email's keywords are unchanged",
      );

      if (my $created = $args->{created}{new}) {
        $tester->request([[ "Email/set" => { destroy => [ $created->{id} ] } ]]);
      }
      $tester->request([[ "Email/set" => { update => { $message->id => { keywords => {} } } } ]]);
    };
  }
};
