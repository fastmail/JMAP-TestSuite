use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;

  subtest "content-* headers forbidden" => sub {
    $tester->request_ok(
      [
        "Email/set" => {
          create => {
            new => {
              mailboxIds => { $mbox->id => \1, },
              'header:Content-foo' => 'bar',
            },
          },
        },
      ],
      superhashof({
        notCreated => {
          new => superhashof({
            type => 'invalidProperties',
            properties => [ 'header:Content-foo' ],
          }),
        },
      }),
      "got invalidProperties error",
    );
  };

  subtest "non content-* headers allowed" => sub {
    $tester->request_ok(
      [
        "Email/set" => {
          create => {
            new => {
              mailboxIds => { $mbox->id => \1, },
              'header:X-Content-foo' => 'bar',
            },
          },
        },
      ],
      superhashof({
        created => {
          new => superhashof({
            id       => jstr(),
            blobId   => jstr(),
            threadId => jstr(),
            size     => jnum(),
          }),
        },
      }),
      "created an email",
    );
  };
};
