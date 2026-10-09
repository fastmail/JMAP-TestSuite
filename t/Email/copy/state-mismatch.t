use jmaptest;

attr pristine  => 1;
attr pool_pairs => 1;

test {
  my ($self) = @_;

  my ($from_account, $to_account) = $self->pool_account_pair;
  my $from_tester = $from_account->tester;
  my $to_tester   = $to_account->tester;

  $from_tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $src_mbox  = $from_account->create_mailbox;
  my $dest_mbox = $to_account->create_mailbox;

  my $state_of = sub {
    my ($tester) = @_;
    my $res = $tester->request([[ "Email/get" => { ids => [] } ]]);
    return $res->single_sentence('Email/get')->arguments->{state};
  };

  my $stale_from = $state_of->($from_tester);
  my $stale_to   = $state_of->($to_tester);
  $src_mbox->add_message({ subject => "advance from state $$" });
  $dest_mbox->add_message({ subject => "advance to state $$" });

  my $copy = sub {
    my ($msg, %arg) = @_;
    return $from_tester->request([[
      "Email/copy" => {
        fromAccountId => $from_account->accountId,
        accountId     => $to_account->accountId,
        %arg,
        create => {
          c1 => { id => $msg->id, mailboxIds => { $dest_mbox->id => jtrue } },
        },
      },
    ]]);
  };

  my $dest_ids = sub {
    my $res = $to_tester->request([[
      "Email/query" => { filter => { inMailbox => $dest_mbox->id } },
    ]]);
    return $res->single_sentence('Email/query')->arguments->{ids};
  };

  # RFC 8620 S5.4: "stateMismatch": An "ifInState" argument was supplied and
  # it does not match the current state, or an "ifFromInState" argument was
  # supplied and it does not match the current state in the from account.
  for my $case (
    [ ifFromInState => $stale_from ],
    [ ifInState     => $stale_to ],
  ) {
    my ($arg, $state) = @$case;

    subtest "stale $arg" => sub {
      my $msg    = $src_mbox->add_message({ subject => "copy $arg $$" });
      my $before = $dest_ids->();
      my $res    = $copy->($msg, $arg => $state);
      jcmp_deeply(
        $res->single_sentence('error')->arguments,
        superhashof({ type => 'stateMismatch' }),
        "got stateMismatch",
      ) or diag explain $res->as_stripped_triples;

      jcmp_deeply($dest_ids->(), $before, "nothing was copied");
    };
  }

  # RFC 8620 S5.4: destroyFromIfInState "is passed on as the "ifInState"
  # argument to the implicit "Foo/set" call".
  subtest "stale destroyFromIfInState" => sub {
    my $msg = $src_mbox->add_message({ subject => "copy destroyFromIfInState $$" });
    my $res = $copy->(
      $msg,
      onSuccessDestroyOriginal => jtrue,
      destroyFromIfInState     => $stale_from,
    );

    my $cid = $res->as_stripped_triples->[0][2];
    jcmp_deeply(
      $res->as_stripped_triples,
      [
        [ 'Email/copy', superhashof({ created => { c1 => superhashof({}) } }), $cid ],
        [ 'error', superhashof({ type => 'stateMismatch' }), $cid ],
      ],
      "copy succeeds and the implicit Email/set fails with stateMismatch",
    ) or diag explain $res->as_stripped_triples;

    $from_tester->request_ok(
      [ "Email/get" => { ids => [ $msg->id ], properties => [ 'id' ] } ],
      superhashof({ list => [ { id => $msg->id } ] }),
      "the original was not destroyed",
    );
  };
};
