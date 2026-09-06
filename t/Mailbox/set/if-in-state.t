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

  my $state_res = $tester->request([[
    "Mailbox/get" => { ids => [] },
  ]]);
  my $state = $state_res->single_sentence('Mailbox/get')->arguments->{state};
  ok($state, 'got current state');

  subtest "correct ifInState is accepted" => sub {
    my $set_res = $tester->request([[
      "Mailbox/set" => {
        ifInState => $state,
        create => {
          new1 => { name => "Test Mailbox" },
        },
      },
    ]]);

    jcmp_deeply(
      $set_res->single_sentence('Mailbox/set')->arguments->{created},
      superhashof({ new1 => ignore() }),
      'mailbox created with correct ifInState'
    );
  };

  subtest "wrong ifInState returns stateMismatch" => sub {
    my $set_res = $tester->request([[
      "Mailbox/set" => {
        ifInState => "bogus-state-that-does-not-exist",
        create => {
          new2 => { name => "Another Mailbox" },
        },
      },
    ]]);

    jcmp_deeply(
      $set_res->single_sentence('error')->arguments,
      superhashof({ type => 'stateMismatch' }),
      'got stateMismatch error for wrong ifInState'
    );
  };
};
