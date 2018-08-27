use jmaptest;

use Data::GUID qw(guid_string);

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
    "respones includes all required properties",
  );
};
