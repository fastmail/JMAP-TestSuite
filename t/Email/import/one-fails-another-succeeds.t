use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mailbox = $account->create_mailbox;

  my $blob = $account->email_blob(generic => {
    body => "This one worked ($$)",
  });
  my $blob2 = $account->email_blob(generic => {
    body => "This one didn't work ($$)",
  });

  my $res = $tester->request([[
    "Email/import" => {
      emails => {
        new => {
          blobId => $blob->blobId,
          mailboxIds => { $mailbox->id => JSON::true },
        },
        new2 => {
          blobId => $blob2->blobId,
          mailboxIds => { "junk" => JSON::true },
        },
      },
    },
  ]]);

  jcmp_deeply(
    $res->single_sentence('Email/import')->arguments,
    {
      accountId  => jstr($account->accountId),
      notCreated => {
        new2 => {
          type => 'invalidProperties',
          properties => [ 'mailboxIds/junk' ], # XXX - Standard?
        },
      },
      created => {
        new => {
          blobId   => jstr(),
          id       => jstr(),
          size     => jnum(),
          threadId => jstr(),
        },
      },
    },
  ) or diag explain $res->as_stripped_triples;

  ok(
    my $id = $res->sentence(0)->arguments->{created}{new}{id},
    'got our email id'
  );

  # Verify mailbox, and message data
  my $verify_res = $tester->request([
    [
      'Email/query' => {
        filter => { inMailbox => $mailbox->id },
      }, 'query',
    ],
    [
      'Email/get' => {
        '#ids' => {
          resultOf => 'query',
          name     => 'Email/query',
          path     => '/ids',
        },
        properties => [ qw(textBody keywords bodyValues receivedAt) ],
        fetchTextBodyValues => JSON::true,
      },
    ],
  ]);

  jcmp_deeply(
    $verify_res->sentence(0)->arguments->{ids},
    [ $id ],
    'Our message was imported to the correct mailbox'
  );

  my $email = $verify_res->sentence_named('Email/get')->arguments->{list}[0];
  my $text_id = $email->{textBody}[0]{partId};

  jcmp_deeply(
    $email,
    superhashof({
      bodyValues => superhashof({
        $text_id => superhashof({
          value => "This one worked ($$)",
        }),
      }),
      receivedAt => re('\A\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\dZ\z'),
    }),
    'email looks good',
  );
};
