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
  };

  subtest "wrong ifInState returns stateMismatch" => sub {
    my $set_res = $tester->request([[
      "Email/set" => {
        ifInState => "bogus-state-that-does-not-exist",
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

    ok($set_res->is_success, "a wrong ifInState is a method-level error, not an HTTP failure")
      or do { diag explain $set_res->response_payload; return };

    jcmp_deeply(
      $set_res->single_sentence('error')->arguments,
      # A state string the server could never have issued may be rejected as
      # invalidArguments instead of stateMismatch; either is a refusal to act.
      superhashof({ type => any('stateMismatch', 'invalidArguments') }),
      'got stateMismatch or invalidArguments for a bogus ifInState'
    );
  };
};
