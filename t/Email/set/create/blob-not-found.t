use jmaptest;

use Data::GUID qw(guid_string);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

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
        new => superhashof({
          type => 'blobNotFound',
          notFound => [ 'cat' ],
        }),
      },
    }),
    "minimum required properties provided gives good response",
  );

  my $good = $tester->upload({
    accountId => $account->accountId,
    type      => 'text/plain',
    blob      => \"good blob $$",
  });
  ok($good->is_success, 'uploaded a blob');

  my $bad_1 = "missing-1-$$";
  my $bad_2 = "missing-2-$$";

  # RFC 8621 S4.6: the "notFound" property lists "every "blobId" referenced
  # by an EmailBodyPart that could not be found on the server".
  for my $case (
    [
      'textBody and attachments' => {
        textBody    => [ { blobId => $good->blobId, type => 'text/plain' } ],
        attachments => [
          { blobId => $bad_1, type => 'application/octet-stream' },
          { blobId => $bad_2, type => 'application/octet-stream' },
        ],
      },
    ],
    [
      'bodyStructure' => {
        bodyStructure => {
          type     => 'multipart/mixed',
          subParts => [
            { blobId => $good->blobId, type => 'text/plain' },
            { blobId => $bad_1, type => 'application/octet-stream' },
            { blobId => $bad_2, type => 'application/octet-stream' },
          ],
        },
      },
    ],
  ) {
    my ($desc, $body) = @$case;

    subtest "two missing blobs among $desc" => sub {
      my $res = $tester->request([[
        "Email/set" => {
          create => {
            new => { mailboxIds => { $mbox->id => jtrue }, %$body },
          },
        },
      ]]);

      jcmp_deeply(
        $res->single_sentence('Email/set')->arguments->{notCreated},
        {
          new => superhashof({
            type     => 'blobNotFound',
            notFound => bag($bad_1, $bad_2),
          }),
        },
        "blobNotFound lists exactly the missing blobs",
      ) or diag explain $res->as_stripped_triples;
    };
  }
};
