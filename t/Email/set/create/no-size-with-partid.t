use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;

  my $blob = $account->email_blob(generic => {
    body => "My pid is $$",
  });

  $tester->request_ok(
    [
      "Email/set" => {
        create => {
          new => {
            mailboxIds => { $mbox->id => jtrue },
            bodyStructure => {
              partId => 'text',
              type   => 'text/plain',
              size   => 2,
            },
            bodyValues => {
              text => {
                value => 'ok',
              }
            },
          },
        },
      },
    ],
    superhashof({
      notCreated => {
        new => {
          type => 'invalidProperties',
          properties => [ 'bodyStructure/size' ],
        },
      },
    }),
    "cannot have size with partId",
  );
};
