use jmaptest;

use Data::GUID qw(guid_string);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;

  my ($create) = $tester->request_ok(
    [
      "Email/set" => {
        create => {
          new => {
            mailboxIds => { $mbox->id => jtrue },
            textBody => [
              {
                partId => 'text1',
                'header:from'  => 'Foo <test@example.org>',
                'header:X-Foo' => 'x-bar',
                'header:subject' => 'a test subject',
                type => 'text/plain',
                cid => 'fooz',
                language => [ 'US' ],
              },
              {
                partId => 'text2',
                'header:from'  => 'Foo <test@example.org>',
                'header:X-Foo' => 'x-bar',
                'header:subject' => 'a test subject',
                type => 'text/plain',
                cid => 'fooz',
                language => [ 'US' ],
              },
            ],
            bodyValues => {
              text1 => {
                value => 'this is a text part1',
              },
              text2 => {
                value => 'this is a text part2',
              }
            },
          },
        },
      },
    ],
    superhashof({
      notCreated => {
        new => {
          type  => 'invalidProperties',
          properties => [ 'textBody' ],
        },
      },
    }),
    "cannot have more than one part in text body"
  );
}
