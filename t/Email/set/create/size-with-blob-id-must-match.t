use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

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

  # RFC 8621 Section 4.6: "If a blobId is given, [size] may be included but
  # is ignored by the server (the size is actually calculated from the blob
  # content itself)". So a wrong size is not an error; the server works out
  # the real one.
  subtest "size doesn't match" => sub {
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
        created => {
          new => superhashof({
            id   => jstr(),
            size => jnum(),
          }),
        },
      }),
      "a mismatched size with blobId is ignored, not rejected",
    );
  };
};
