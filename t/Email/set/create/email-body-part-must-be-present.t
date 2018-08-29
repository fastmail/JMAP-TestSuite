use jmaptest;

use Data::GUID qw(guid_string);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;

  TODO: {
    local $TODO = 'foo';

    $tester->request_ok(
      [
        "Email/set" => {
          create => {
            new => {
              mailboxIds => { $mbox->id => jtrue },
              bodyStructure => {
                partId => 'text',
                type   => 'text/plain',
              },
              bodyValues => {
                notText => {
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
            properties => [ 'bodyStructure/partId' ],
          },
        },
      }),
      "partId must be present in bodyValues",
    );
  };
};
