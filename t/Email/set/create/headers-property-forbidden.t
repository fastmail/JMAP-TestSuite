use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;

  $tester->request_ok(
    [
      "Email/set" => {
        create => {
          new => {
            mailboxIds => { $mbox->id => \1, },
            headers => [{ name => 'foo', value => 'bar' }],
          },
        },
      },
    ],
    superhashof({
      notCreated => {
        new => superhashof({
          type => 'invalidProperties',
          properties => [ 'headers' ],
        }),
      },
    }),
    "got invalidProperties error",
  );
};
