use jmaptest;

attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mailbox = $account->create_mailbox;

  my $blob = $account->email_blob(generic => {});
  ok($blob->is_success, 'uploaded blob');

  # Read the state after all setup; a server may advance it for its own
  # reasons, e.g. Cyrus does on a blob upload.
  my $state_res = $tester->request([[
    "Email/get" => { ids => [] },
  ]]);
  my $state = $state_res->single_sentence('Email/get')->arguments->{state};
  ok($state, 'got current state');

  my $new1_id;

  subtest "correct ifInState is accepted" => sub {
    my $set_res = $tester->request([[
      "Email/set" => {
        ifInState => $state,
        create => {
          new1 => {
            mailboxIds => { $mailbox->id => JSON::true },
            subject    => "Test",
            bodyStructure => {
              type    => 'text/plain',
              partId  => 'body',
            },
            bodyValues => {
              body => { value => "Test body" },
            },
          },
        },
      },
    ]]);

    jcmp_deeply(
      $set_res->single_sentence('Email/set')->arguments->{created},
      superhashof({ new1 => ignore() }),
      'email created with correct ifInState'
    );

    $new1_id = $set_res->single_sentence('Email/set')->arguments->{created}{new1}{id};
  };

  subtest "stale ifInState returns stateMismatch" => sub {
    # $state was current before new1 was created, so it is now stale.
    my $set_res = $tester->request([[
      "Email/set" => {
        ifInState => $state,
        create => {
          new2 => {
            mailboxIds => { $mailbox->id => JSON::true },
            subject    => "Test 2",
            bodyStructure => {
              type    => 'text/plain',
              partId  => 'body',
            },
            bodyValues => {
              body => { value => "Test body 2" },
            },
          },
        },
      },
    ]]);

    ok($set_res->is_success, "a stale ifInState is a method-level error, not an HTTP failure")
      or do { diag explain $set_res->response_payload; return };

    # RFC 8620 S5.3: on a mismatch "the method will be aborted and a
    # "stateMismatch" error returned".
    jcmp_deeply(
      $set_res->single_sentence('error')->arguments,
      superhashof({ type => 'stateMismatch' }),
      'got stateMismatch for a stale ifInState'
    ) or diag explain $set_res->as_stripped_triples;

    # RFC 8620 S3.6.2: after a method-level error the server state "MUST NOT
    # have changed", so new2 must not exist.
    my $query_res = $tester->request([[
      "Email/query" => { filter => { inMailbox => $mailbox->id } },
    ]]);
    jcmp_deeply(
      $query_res->single_sentence('Email/query')->arguments->{ids},
      [ $new1_id ],
      'the create in the rejected call did not happen'
    ) or diag explain $query_res->as_stripped_triples;
  };
};
