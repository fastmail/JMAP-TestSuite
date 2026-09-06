use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  # Add a message to make sure we don't get it
  $account->create_mailbox->add_message;

  my $res = $tester->request_ok(
    [ "Email/get" => { ids => [] } ],
    superhashof({
      accountId => jstr($account->accountId),
      state     => jstr(),
      list      => [],
    }),
    "Response for ids => [] looks good"
  );
};
