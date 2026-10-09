use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $parent = $account->create_mailbox;

  my $session = fetch_session($tester) or return;
  my $max = $session->{accounts}{ $account->accountId }{accountCapabilities}
              {"urn:ietf:params:jmap:mail"}{maxSizeMailboxName};

  # RFC 8621 S2: name "MUST be a Net-Unicode string [RFC5198] of at least 1
  # character in length, subject to the maximum size given in the capability
  # object"; S1.3.1 gives maxSizeMailboxName in UTF-8 octets.
  my @cases = ([ "empty name" => '' ]);
  if (defined $max) {
    push @cases, (
      [ "ASCII name over maxSizeMailboxName" => 'x' x ($max + 1) ],
      [ "name over maxSizeMailboxName in octets, not characters"
          => "\x{e9}" x (int($max / 2) + 1) ],
    );
  } else {
    note("mail capability has no maxSizeMailboxName; skipping length cases");
  }

  for my $case (@cases) {
    my ($desc, $name) = @$case;

    subtest $desc => sub {
      my $res = $tester->request([[
        "Mailbox/set" => {
          create => { bad => { name => $name, parentId => $parent->id } },
        },
      ]]);
      ok($res->is_success, "Mailbox/set") or diag explain $res->response_payload;

      my $args = $res->single_sentence("Mailbox/set")->arguments;
      ok(!$args->{created}{bad}, "Mailbox not created") or diag explain $args;
      jcmp_deeply(
        $args->{notCreated}{bad},
        any(invalid_properties('name'), superhashof({ type => 'tooLarge' })),
        "notCreated with invalidProperties or tooLarge",
      ) or diag explain $args;
    };
  }
};
