use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  # First, figure out our defaults. See if they are consistent across
  # at least two creates
  my $mailbox1 = $account->create_mailbox;
  my $mailbox2 = $account->create_mailbox;

  my @immutable = qw(
    totalEmails
    unreadEmails
    totalThreads
    unreadThreads
  );

  my @immutable_rights = qw(
    mayReadItems
    mayAddItems
    mayRemoveItems
    maySetSeen
    maySetKeywords
    mayCreateChild
    mayRename
    mayDelete
    maySubmit
  );

  for my $f (@immutable, @immutable_rights) {
    unless ($mailbox1->$f eq $mailbox2->$f) {
      plan skip_all => "$f differed with two fresh mailboxes. Cannot test without predictable values";
    }
  }

  my $get_res = $tester->request({
    methodCalls => [[
      "Mailbox/get" => { ids => [ $mailbox1->id ] },
    ]],
  });

  my $mb = $get_res->single_sentence('Mailbox/get')->arguments->{list}[0];
  ok($mb, 'got a fresh mailbox');

  delete($mb->{id});

  subtest "immutable properties with correct values is okay" => sub {
    TODO: {
      $mb->{name} .= " a change";

      local $TODO = "https://github.com/cyrusimap/cyrus-imapd/issues/2315"
        if $self->server->isa('JMAP::TestSuite::ServerAdapter::Cyrus');

      my $res = $tester->request({
        methodCalls => [[
          "Mailbox/set" => {
            create => {
              new => $mb,
            },
          },
        ]],
      });

      ok($res->is_success, "Mailbox/set create")
        or diag explain $res->http_response->as_string;

      my $sentence = $res->sentence(0);
      is($sentence->name, "Mailbox/set", 'got correct sentence');
      ok(
        $sentence->arguments->{created}{new},
        "created our mailbox passing in immutable params!"
      ) or diag explain $res->as_stripped_triples;
    }
  };

  subtest "immutable properties with wrong values is not okay" => sub {
    $mb->{name} .= " and another";
    $mb->{id} = $mailbox1->id;

    my %rights = map {;
      $_ => $mailbox1->$_ ? JSON::false : JSON::true
    } keys %{ $mailbox1->myRights };

    $mb->{myRights} = \%rights;
    $mb->{$_} = 52 for qw(
      totalEmails
      unrealEmails
      totalThreads
      unreadThreads
    );

    my $set_res = $tester->request({
      methodCalls => [[
        "Mailbox/set" => {
          create => {
            new => $mb,
          },
        },
      ]],
    });

   TODO: {
     local $TODO = "https://github.com/cyrusimap/cyrus-imapd/issues/2316"
       if $self->server->isa('JMAP::TestSuite::ServerAdapter::Cyrus');

      jcmp_deeply(
        $set_res->single_sentence('Mailbox/set')->arguments->{notCreated}{new},
        {
          type => 'invalidProperties',
          properties => bag(
            qw(
              id
              totalEmails
              unreadEmails
              totalThreads
              unreadThreads
            ),
            map {; "myRights/$_" } keys %rights,
          ),
        },
        'got errors for immutable properties'
      ) or diag explain $set_res->as_stripped_triples;
    }
  };
};
