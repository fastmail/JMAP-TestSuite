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
            htmlBody => [
              {
                partId => 'html1',
                'header:from'  => 'Foo <test@example.org>',
                'header:X-Foo' => 'x-bar',
                'header:subject' => 'a test subject',
                type => 'text/html',
                cid => 'fooz',
                language => [ 'US' ],
              },
              {
                partId => 'html2',
                'header:from'  => 'Foo <test@example.org>',
                'header:X-Foo' => 'x-bar',
                'header:subject' => 'a test subject',
                type => 'text/html',
                cid => 'fooz',
                language => [ 'US' ],
              },
            ],
            bodyValues => {
              html1 => {
                value => 'this is a text in part1',
              },
              html2 => {
                value => 'this is a text in part2',
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
          properties => [ 'htmlBody' ],
        },
      },
    }),
    "cannot have more than one part in html body"
  );
}
