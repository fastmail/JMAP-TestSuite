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
            bodyStructure => {
              headers => [{ name => 'foo', value => 'bar' }],
              partId => 'text',
              type   => 'text/plain',
            },
            bodyValues => {
              text => {
                value => 'email',
              },
            },
          },
        },
      },
    ],
    superhashof({
      notCreated => {
        new => superhashof({
          type => 'invalidProperties',
          properties => [ 'bodyStructure/headers' ],
        }),
      },
    }),
    "got invalidProperties error",
  );
};
