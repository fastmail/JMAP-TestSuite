use jmaptest;

use Data::GUID qw(guid_string);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;

  subtest "no properties" => sub {
    $tester->request_ok(
      [
        "Email/set" => {
          create => {
            new => {},
          },
        },
      ],
      superhashof({
        notCreated => {
          new => {
            type => 'invalidProperties',
            properties => [ 'mailboxIds' ],
          },
        },
      }),
      "required properties not provided gives correct error",
    );
  };

  subtest "minimum required properties" => sub {
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
            id => jstr(),
          }),
        },
      }),
      "minimum required properties provided gives good response",
    );
  };
};
