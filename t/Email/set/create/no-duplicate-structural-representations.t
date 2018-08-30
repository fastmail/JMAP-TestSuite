use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;

  my $blob = $account->email_blob(generic => {});

  # bodyStructure is provided so textBody/htmlBody/attachments cannot be
  $tester->request_ok(
    [
      "Email/set" => {
        create => {
          new => {
            mailboxIds => { $mbox->id => \1, },
            bodyStructure => {
              partId => 'text',
              type   => 'text/plain',
            },
            textBody => [
              {
                partId => 'textbody',
                type   => 'text/plain',
              },
            ],
            htmlBody => [
              {
                partId => 'htmlbody',
                type   => 'text/html',
              },
            ],
            attachments => [
              {
                blobId => $blob->blob_id,
                type   => 'text/plain',
              },
            ],
            bodyValues => {
              text => { value => 'foo' },
              textbody => { value => 'bar' },
              htmlbody => { value => 'baz' },
            },
          },
        },
      },
    ],
    superhashof({
      notCreated => {
        new => superhashof({
          type => 'invalidProperties',
          properties => [qw(
            textBody
            htmlBody
            attachments
          )],
        }),
      },
    }),
    "got invalidProperties error",
  );
};
