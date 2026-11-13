use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mbox_1  = $account->create_mailbox;
  my $mbox_2  = $account->create_mailbox;
  my $message = $mbox_1->add_message({
    subject  => "patches $$",
    keywords => { '$flagged' => jtrue },
  });
  my $id = $message->id;

  # RFC 8620 S5.3: a patch key is a JSON pointer; null removes the key and
  # anything else sets it, leaving the rest of the object alone.
  my $patch_ok = sub {
    my ($patch, $want, $desc) = @_;

    subtest $desc => sub {
      my $res = $tester->request([[
        "Email/set" => { update => { $id => $patch } },
      ]]);
      jcmp_deeply(
        $res->single_sentence('Email/set')->arguments->{updated},
        { $id => any(undef, superhashof({})) },
        "update succeeded",
      ) or diag explain $res->as_stripped_triples;

      $tester->request_ok(
        [ "Email/get" => { ids => [ $id ], properties => [ keys %$want ] } ],
        superhashof({ list => [ { id => $id, %$want } ] }),
        "email has the patched value",
      );
    };
  };

  $patch_ok->(
    { 'keywords/$seen' => jtrue },
    { keywords => { '$flagged' => jtrue, '$seen' => jtrue } },
    'patch keywords/$seen to true adds it',
  );

  $patch_ok->(
    { 'keywords/$seen' => undef },
    { keywords => { '$flagged' => jtrue } },
    'patch keywords/$seen to null removes it',
  );

  $patch_ok->(
    { 'mailboxIds/' . $mbox_2->id => jtrue },
    { mailboxIds => { $mbox_1->id => jtrue, $mbox_2->id => jtrue } },
    'patch mailboxIds/<id> to true adds a second mailbox',
  );
};
