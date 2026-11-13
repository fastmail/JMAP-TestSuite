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
  my $message = $mbox->add_message({ subject => "mailboxIds not empty $$" });
  my $mbox_id = $mbox->id;

  # RFC 8621 S4.1.1: an Email "MUST belong to one or more Mailboxes at all
  # times (until it is destroyed)".
  for my $case (
    [ "set mailboxIds to {}"         => { mailboxIds => {} } ],
    [ "patch out the only mailbox"   => { "mailboxIds/$mbox_id" => undef } ],
  ) {
    my ($desc, $patch) = @$case;

    subtest $desc => sub {
      my $res = $tester->request([[
        "Email/set" => { update => { $message->id => $patch } },
      ]]);

      jcmp_deeply(
        $res->single_sentence('Email/set')->arguments->{notUpdated},
        { $message->id => invalid_properties('mailboxIds') },
        "update leaving no mailboxes is rejected",
      ) or diag explain $res->as_stripped_triples;

      $tester->request_ok(
        [ "Email/get" => { ids => [ $message->id ], properties => [ 'mailboxIds' ] } ],
        superhashof({
          list => [ { id => $message->id, mailboxIds => { $mbox_id => jtrue } } ],
        }),
        "email is still in its mailbox",
      );
    };
  }
};
