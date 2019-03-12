use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mailbox = $account->create_mailbox;
  my $blob = $tester->upload({
    accountId => $account->accountId,
    type      => 'text/plain',
    blob      => \"some data"
  });

  my $res = $tester->request([[
    "Email/import" => {
      emails => {
        new => {
          blobId     => $blob->blobId,
          mailboxIds => { $mailbox->id => JSON::true },
        },
      },
    },
  ]]);

  TODO: {
    todo_skip "Need to figure out what to do here", 1;
    ok(1);
  };
};
