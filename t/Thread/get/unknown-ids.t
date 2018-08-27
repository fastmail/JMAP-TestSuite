use jmaptest;

attr pristine => 1;

# We use ->pristine_account directly so we must support pristine
test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $other_account = $self->pristine_account;
  my $other_mailbox = $other_account->create_mailbox;
  my $other_message = $other_mailbox->add_message;

  # Thread is in another account so we shouldn't see it, therefore
  # notFound!
  my $get_res = $tester->request([[
    "Thread/get" => { ids => [ $other_message->threadId ] },
  ]]);

  jcmp_deeply(
    $get_res->sentence_named('Thread/get')->arguments,
    {
      accountId => jstr($account->accountId),
      state => jstr(),
      list => [],
      notFound => [ jstr($other_message->threadId) ],
    },
    "Thread/get fills in notFound for messages in another account",
  );
};
