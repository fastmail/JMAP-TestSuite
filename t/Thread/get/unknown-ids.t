use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  # RFC 8620 S1.2: ids are unique only per type per account, so another
  # account's threadId could also exist here.
  my $unknown_id = 'jmts-no-such-thread-' . time . '-' . $$;

  my $get_res = $tester->request([[
    "Thread/get" => { ids => [ $unknown_id ] },
  ]]);

  jcmp_deeply(
    $get_res->sentence_named('Thread/get')->arguments,
    {
      accountId => jstr($account->accountId),
      state => jstr(),
      list => [],
      notFound => [ jstr($unknown_id) ],
    },
    "Thread/get fills in notFound for unknown ids",
  );
};
