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
            textBody => [
              { blobId => 'cat' },
            ],
          },
        },
      },
    ],
    superhashof({
      notCreated => {
        new => {
          type => 'blobNotFound',
          notFound => [ 'cat' ],
        },
      },
    }),
    "minimum required properties provided gives good response",
  );
};
