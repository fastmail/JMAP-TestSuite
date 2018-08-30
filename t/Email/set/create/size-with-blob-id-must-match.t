use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;

  my $blob = $account->email_blob(generic => {});

  subtest "size matches" => sub {
    $tester->request_ok(
      [
        "Email/set" => {
          create => {
            new => {
              mailboxIds => { $mbox->id => jtrue },
              bodyStructure => {
                blobId => $blob->blob_id,
                type   => 'text/plain',
                size   => $blob->size,
              },
            },
          },
        },
      ],
      superhashof({
        created => {
          new => superhashof({
            id => jstr(),
          }),
        },
      }),
      "can have size with blobId if it matches",
    );
  };

  subtest "size doesn't match" => sub {
    TODO: {
      local $TODO = 'https://github.com/cyrusimap/cyrus-imapd/issues/2501';

      $tester->request_ok(
        [
          "Email/set" => {
            create => {
              new => {
                mailboxIds => { $mbox->id => jtrue },
                bodyStructure => {
                  blobId => $blob->blob_id,
                  type   => 'text/plain',
                  size   => $blob->size + 5,
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
        "cannot have mismatched size with blobId",
      );
    };
  };
};
