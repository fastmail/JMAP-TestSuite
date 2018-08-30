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
              partId => 'text',
              type   => 'text/plain',
              'header:Content-Transfer-Encoding' => '7BIT',
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
        new => {
          type => 'invalidProperties',
          properties => [ 'bodyStructure/header:Content-Transfer-Encoding' ],
        },
      },
    }),
    "cannot specify Content-Transfer-Encoding",
  );
};
