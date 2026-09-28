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

  my $msg = $src_mbox->add_message({ body => "test body $$" });

  subtest "basic copy" => sub {
    my $res = $from_tester->request([[
      "Email/copy" => {
        fromAccountId => $from_account->accountId,
        accountId     => $to_account->accountId,
        create => {
          c1 => {
            id         => $msg->id,
            mailboxIds => { $dest_mbox->id => JSON::true },
          },
        },
      },
    ]]);
    ok($res->is_success, "Email/copy") or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("Email/copy")->arguments,
      {
        fromAccountId => jstr($from_account->accountId),
        accountId     => jstr($to_account->accountId),
        oldState      => jstr(),
        newState      => jstr(),
        created       => { c1 => superhashof({ id => jstr() }) },
        notCreated    => undef,
      },
      "Email/copy response looks right",
    ) or diag explain $res->as_stripped_triples;

    my $new_id = $res->single_sentence("Email/copy")->arguments->{created}{c1}{id};

    my $verify = $to_tester->request([[
      "Email/get" => {
        accountId  => $to_account->accountId,
        ids        => [ $new_id ],
        properties => [ qw(mailboxIds) ],
      },
    ]]);
    jcmp_deeply(
      $verify->single_sentence("Email/get")->arguments->{list}[0]{mailboxIds},
      { $dest_mbox->id => JSON::true },
      "email landed in correct destination mailbox",
    ) or diag explain $verify->as_stripped_triples;

    my $orig = $from_tester->request([[
      "Email/get" => {
        accountId => $from_account->accountId,
        ids       => [ $msg->id ],
      },
    ]]);
    ok(
      $orig->single_sentence("Email/get")->arguments->{list}[0],
      "original email still exists in source account",
    );
  };

  subtest "onSuccessDestroyOriginal" => sub {
    my $msg2 = $src_mbox->add_message({ body => "delete me $$" });

    my $res = $from_tester->request([[
      "Email/copy" => {
        fromAccountId          => $from_account->accountId,
        accountId              => $to_account->accountId,
        onSuccessDestroyOriginal => JSON::true,
        create => {
          c2 => {
            id         => $msg2->id,
            mailboxIds => { $dest_mbox->id => JSON::true },
          },
        },
      },
    ]]);
    ok($res->is_success, "Email/copy with onSuccessDestroyOriginal")
      or diag explain $res->response_payload;

    my $args = $res->sentence_named("Email/copy")->arguments;
    ok($args->{created}{c2}, "email was copied");

    my $set_args = $res->sentence_named("Email/set")->arguments;
    ok(grep { $_ eq $msg2->id } @{$set_args->{destroyed} // []},
       "Email/set response shows original destroyed");

    my $check = $from_tester->request([[
      "Email/get" => {
        accountId => $from_account->accountId,
        ids       => [ $msg2->id ],
      },
    ]]);
    jcmp_deeply(
      $check->single_sentence("Email/get")->arguments->{notFound},
      [ $msg2->id ],
      "original email was destroyed after copy",
    ) or diag explain $check->as_stripped_triples;
  };
};
