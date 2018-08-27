use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  subtest "single mailbox import, all values" => sub {
    my $blob = $account->email_blob(generic => {
      body => "My pid is $$",
    });

    my $mailbox = $account->create_mailbox;

    my $res = $tester->request([[
      "Email/import" => {
        emails => {
          new => {
            blobId => $blob->blobId,
            mailboxIds => { $mailbox->id => JSON::true },
            keywords   => { 'Foo' => JSON::true },
            receivedAt => '2017-08-08T05:04:03Z',
          },
        },
      },
    ]]);

    jcmp_deeply(
      $res->single_sentence('Email/import')->arguments,
      {
        accountId  => jstr($account->accountId),
        notCreated => {},
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
            value => "My pid is $$",
          }),
        }),
        receivedAt => jstr('2017-08-08T05:04:03Z'),
        keywords   => superhashof({ 'foo' => JSON::true }),
      }),
      'email looks good',
    );
  };

  subtest "single mailbox import, default values" => sub {
    my $blob = $account->email_blob(generic => {
      body => "My pid is still $$",
    });

    my $mailbox = $account->create_mailbox;

    my $res = $tester->request([[
      "Email/import" => {
        emails => {
          new => {
            blobId => $blob->blobId,
            mailboxIds => { $mailbox->id => JSON::true },
          },
        },
      },
    ]]);

    jcmp_deeply(
      $res->single_sentence('Email/import')->arguments,
      {
        accountId  => jstr($account->accountId),
        notCreated => {},
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
            value => "My pid is still $$",
          }),
        }),
        receivedAt => re('\A\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\dZ\z'),
      }),
      'email looks good',
    );
  };

  subtest "multiple mailboxes" => sub {
    my $blob = $account->email_blob(generic => {
      body => "Still $$ for my pid",
    });

    my $mailbox = $account->create_mailbox;
    my $mailbox2 = $account->create_mailbox;

    my $res = $tester->request([[
      "Email/import" => {
        emails => {
          new => {
            blobId => $blob->blobId,
            mailboxIds => {
              $mailbox->id  => JSON::true,
              $mailbox2->id => JSON::true,
            },
          },
        },
      },
    ]]);

    jcmp_deeply(
      $res->single_sentence('Email/import')->arguments,
      {
        accountId  => jstr($account->accountId),
        notCreated => {},
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

    for my $mailbox_id ($mailbox->id, $mailbox2->id) {
      # Verify mailbox, and message data
      my $verify_res = $tester->request([
        [
          'Email/query' => {
            filter => { inMailbox => $mailbox_id },
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
              value => "Still $$ for my pid",
            }),
          }),
          receivedAt => re('\A\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\dZ\z'),
        }),
        'email looks good',
      );
    }
  };
};
