use jmaptest;

use Data::GUID qw(guid_string);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;

  my $blob = $tester->upload({
    accountId => $account->accountId,
    type      => 'text/plain',
    blob      => \"Hello there",
  });

  my ($create) = $tester->request_ok(
    [
      "Email/set" => {
        create => {
          new => {
            mailboxIds => { $mbox->id => jtrue },
            htmlBody => [
              {
                blobId => $blob->blobId,
                'header:from'  => 'Foo <test@example.org>',
                'header:X-Foo' => 'x-bar',
                'header:subject' => 'a test subject',
                type => 'text/html',
                cid => 'fooz',
                language => [ 'US' ],
              },
            ],
          },
        },
      },
    ],
    superhashof({
      created => {
        new => {
          id       => jstr(),
          size     => jnum(),
          blobId   => jstr(),
          threadId => jstr(),
        },
      },
    }),
    "htmlBody create"
  );

  my $new = $create->sentence(0)->arguments->{created}{new};
  my $id = $new->{id};
  ok($id, 'got the id');

  my %body = (
    blobId      => $blob->blobId,
    charset     => 'us-ascii',
    cid         => 'fooz',
    disposition => undef,
    language    => [ 'US' ],
    location    => undef,
    name        => undef,
    partId      => jstr(),
    size        => jnum(),
    type        => 'text/html',
  );

  my ($res) = $tester->request_ok(
    [
      "Email/get" => {
        ids => [ $id ],
        fetchHTMLBodyValues => jtrue(),
      },
    ],
    superhashof({
      list => [
        {
          attachments => [],
          bcc         => undef,
          blobId      => $new->{blobId},
          bodyValues  => ignore(), # will validate after
          cc          => undef,
          from        => [
            {
              name => 'Foo',
              email => 'test@example.org',
            },
          ],
          hasAttachment => jfalse,
          htmlBody    => [ \%body ],
          id          => $id,
          inReplyTo   => undef,
          keywords    => {},
          mailboxIds  => {
            $mbox->id => jtrue(),
          },
          messageId   => [ jstr(), ],
          preview     => jstr(),
          receivedAt  => re('^\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\dZ\z'),
          references  => undef,
          replyTo     => undef,
          sender      => undef,
          sentAt      => re('\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d(Z|([+-]\d\d:\d\d))\z'),
          size        => jnum(),
          subject     => 'a test subject',
          textBody    => [ \%body ],
          threadId    => $new->{threadId},
          to          => undef,
        },
      ],
    }),
    'get looks good'
  );

  my $email = $res->sentence(0)->arguments->{list}[0];

  my $text_body = $email->{htmlBody}[0];
  my $body_value = $email->{bodyValues}{ $text_body->{partId} };

  ok($body_value, 'got our body value');
  jcmp_deeply(
    $body_value,
    {
      isEncodingProblem => jfalse(),
      isTruncated       => jfalse(),
      value             => 'Hello there',
    },
  );
};
