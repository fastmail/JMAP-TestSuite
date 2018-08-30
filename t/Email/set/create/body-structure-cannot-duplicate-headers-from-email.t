use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;

  TODO: {
    local $TODO = 'https://github.com/cyrusimap/cyrus-imapd/issues/2498';
    $tester->request_ok(
      [
        "Email/set" => {
          create => {
            new => {
              mailboxIds => { $mbox->id => \1, },
              'header:foo' => 'bar',
              bodyStructure => {
                partId => 'text',
                type   => 'text/plain',
                'header:foo' => 'bar',
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
            properties => [ 'bodyStructure/header:foo' ],
          },
        },
      }),
      "got invalidProperties error",
    );
  };
};
