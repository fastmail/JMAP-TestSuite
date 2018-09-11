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
            bodyStructure => {
              'header:from'  => 'Foo <test@example.org>',
              'header:X-Foo' => 'x-bar',
              'header:subject' => 'a test subject',
              type => 'multipart/mixed',
              subParts => [
                {
                  partId => 'text',
                  type => 'text/plain',
                  cid => 'fooz',
                  language => [ 'US' ],
                },
                {
                  partId => 'text2',
                },
              ],
            },
            bodyValues => {
              text => {
                value => 'this is a text part',
              },
              text2 => {
                value => 'this is a second text part',
              },
            },
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
    "textBody create"
  );

  my $new = $create->sentence(0)->arguments->{created}{new};
  my $id = $new->{id};
  ok($id, 'got the id');

  my %body = (
    blobId      => jstr(),
    charset     => 'us-ascii',
    cid         => undef,
    disposition => undef,
    language    => undef,
    location    => undef,
    name        => undef,
    partId      => jstr(),
    size        => jnum(),
    type        => 'text/plain',
  );

  my ($res) = $tester->request_ok(
    [
      "Email/get" => {
        ids => [ $id ],
        fetchTextBodyValues => jtrue(),
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
          htmlBody    => [
            { %body, language => [ 'US' ], cid => 'fooz', },
            { %body, },
          ],
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
          sentAt      => re('^\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\dZ\z'),
          size        => jnum(),
          subject     => 'a test subject',
          textBody    => [
            { %body, language => [ 'US' ], cid => 'fooz', },
            { %body, },
          ],
          threadId    => $new->{threadId},
          to          => undef,
        },
      ],
    }),
    'get looks good'
  );

  my $email = $res->sentence(0)->arguments->{list}[0];

  my $text_body_1 = $email->{textBody}[0];
  my $body_value_1 = $email->{bodyValues}{ $text_body_1->{partId} };

  my $text_body_2 = $email->{textBody}[1];
  my $body_value_2 = $email->{bodyValues}{ $text_body_2->{partId} };

  ok($body_value_1, 'got our body value');
  jcmp_deeply(
    $body_value_1,
    {
      isEncodingProblem => jfalse(),
      isTruncated       => jfalse(),
      value             => 'this is a text part',
    },
  );

  ok($body_value_2, 'got our body value');
  jcmp_deeply(
    $body_value_2,
    {
      isEncodingProblem => jfalse(),
      isTruncated       => jfalse(),
      value             => 'this is a second text part',
    },
  );
};
