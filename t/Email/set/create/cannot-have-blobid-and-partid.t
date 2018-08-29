use jmaptest;

use Data::GUID qw(guid_string);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;

  my $blob = $account->email_blob(generic => {
    body => "My pid is $$",
  });

  TODO: {
    local $TODO = 'foo';

    $tester->request_ok(
      [
        "Email/set" => {
          create => {
            new => {
              mailboxIds => { $mbox->id => jtrue },
              bodyStructure => {
                blobId => $blob->blobId,
                partId => 'text',
                type   => 'text/plain',
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
            properties => bag(qw(bodyStructure/partId bodyStructure/blobId)),
          },
        },
      }),
      "cannot have blobId and partId in bodyStructure",
    );
  };
};
