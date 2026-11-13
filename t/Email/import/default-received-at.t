use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mailbox = $account->create_mailbox;

  # The newest Received header is the topmost one (RFC 5321 S4.4).
  my $blob = $account->email_blob(generic => {
    subject     => "default receivedAt $$",
    raw_headers => [
      Received => 'from relay.example.net by mx.example.com; Tue, 03 Mar 2015 10:20:30 +0000',
      Received => 'from client.example.org by relay.example.net; Tue, 03 Mar 2015 09:00:00 +0000',
    ],
  });
  ok($blob->is_success, 'uploaded blob');

  my $res = $tester->request([[
    "Email/import" => {
      emails => {
        new => { blobId => $blob->blobId, mailboxIds => { $mailbox->id => jtrue } },
      },
    },
  ]]);
  my $id = $res->single_sentence('Email/import')->arguments->{created}{new}{id};
  ok($id, 'imported the message') or return diag explain $res->as_stripped_triples;

  # RFC 8621 S4.8: receivedAt has "default: time of most recent Received
  # header, or time of import on server if none".
  $tester->request_ok(
    [ "Email/get" => { ids => [ $id ], properties => [ 'receivedAt' ] } ],
    superhashof({ list => [ { id => $id, receivedAt => '2015-03-03T10:20:30Z' } ] }),
    'receivedAt defaults to the most recent Received header',
  );
};
