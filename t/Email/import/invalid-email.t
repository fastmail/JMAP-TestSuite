use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mailbox = $account->create_mailbox;
  my $blob = $tester->upload({
    accountId => $account->accountId,
    type      => 'text/plain',
    blob      => \"some data"
  });

  my $res = $tester->request([[
    "Email/import" => {
      emails => {
        new => {
          blobId     => $blob->blobId,
          mailboxIds => { $mailbox->id => JSON::true },
        },
      },
    },
  ]]);

  # RFC 8621 S4.8: the server may fix an invalid message, and then the blobId
  # "MUST ... be different", or it may reject it with invalidEmail.
  jcmp_deeply(
    $res->single_sentence('Email/import')->arguments,
    any(
      superhashof({
        created => {
          new => superhashof({ id => jstr(), blobId => none($blob->blobId) }),
        },
      }),
      superhashof({
        notCreated => { new => superhashof({ type => 'invalidEmail' }) },
      }),
    ),
    "invalid message is either fixed or rejected with invalidEmail",
  ) or diag explain $res->as_stripped_triples;
};
