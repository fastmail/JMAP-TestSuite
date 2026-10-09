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
  my $blob    = $account->email_blob(generic => { subject => "import ifInState $$" });
  ok($blob->is_success, 'uploaded blob');

  my $state_res = $tester->request([[ "Email/get" => { ids => [] } ]]);
  my $state = $state_res->single_sentence('Email/get')->arguments->{state};
  ok($state, 'got current state');

  $mailbox->add_message({ subject => "advance the state $$" });

  my $before = $tester->request([[
    "Email/query" => { filter => { inMailbox => $mailbox->id } },
  ]])->single_sentence('Email/query')->arguments->{ids};

  my $res = $tester->request([[
    "Email/import" => {
      ifInState => $state,
      emails => {
        new => { blobId => $blob->blobId, mailboxIds => { $mailbox->id => jtrue } },
      },
    },
  ]]);

  # RFC 8621 S4.8: if ifInState does not match "the method will be aborted
  # and a "stateMismatch" error returned".
  jcmp_deeply(
    $res->single_sentence('error')->arguments,
    superhashof({ type => 'stateMismatch' }),
    'got stateMismatch for a stale ifInState',
  ) or diag explain $res->as_stripped_triples;

  $tester->request_ok(
    [ "Email/query" => { filter => { inMailbox => $mailbox->id } } ],
    superhashof({ ids => $before }),
    'nothing was imported',
  );
};
