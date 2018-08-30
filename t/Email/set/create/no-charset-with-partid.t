use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;

  my $blob = $account->email_blob(generic => {
    body => "My pid is $$",
  });

  TODO: {
    local $TODO = 'https://github.com/cyrusimap/cyrus-imapd/issues/2500';

    $tester->request_ok(
      [
        "Email/set" => {
          create => {
            new => {
              mailboxIds => { $mbox->id => jtrue },
              bodyStructure => {
                partId  => 'text',
                type    => 'text/plain',
                charset => 'us-ascii',
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
            properties => [ 'bodyStructure/charset' ],
          },
        },
      }),
      "cannot have charset with partId",
    );
  };
};
