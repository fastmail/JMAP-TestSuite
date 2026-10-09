use jmaptest;

attr pristine  => 1;
attr pool_pairs => 1;

test {
  my ($self) = @_;

  my ($from_account, $to_account) = $self->pool_account_pair;
  my $from_tester = $from_account->tester;

  $from_tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $dest_mbox = $to_account->create_mailbox;

  # RFC 8620 S5.4: a copy may fail with any standard /set error, and S5.3:
  # "If an id given cannot be found, the update or destroy MUST be rejected
  # with a "notFound" set error."
  my $res = $from_tester->request([[
    "Email/copy" => {
      fromAccountId => $from_account->accountId,
      accountId     => $to_account->accountId,
      create => {
        c1 => { id => 'nonexistent', mailboxIds => { $dest_mbox->id => jtrue } },
      },
    },
  ]]);

  jcmp_deeply(
    $res->single_sentence('Email/copy')->arguments->{notCreated},
    { c1 => superhashof({ type => 'notFound' }) },
    "copying a nonexistent email gives notFound",
  ) or diag explain $res->as_stripped_triples;
};
