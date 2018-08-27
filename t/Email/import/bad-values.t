use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  subtest "emails -> wrong form" => sub {
    for my $bad (undef, "none", ["foo"]) {
      my $res = $tester->request([[
        "Email/import" => {
          emails => $bad,
        },
      ]]);

      jcmp_deeply(
        $res->single_sentence('error')->arguments,
        {
          type => 'invalidArguments',
          arguments => [ 'emails' ], # XXX - Not to spec, but cyrus gives it
        },
        "got error about bad 'emails'"
      ) or diag explain $res->as_stripped_triples;
    }
  };

  subtest "emails -> required" => sub {
    my $res = $tester->request([[
      "Email/import" => {},
    ]]);

    jcmp_deeply(
      $res->single_sentence('error')->arguments,
      {
        type => 'invalidArguments',
        arguments => [ 'emails' ], # XXX - Not to spec, but cyrus gives it
      },
      "got error about bad 'emails'"
    ) or diag explain $res->as_stripped_triples;
  };

  my $blob = $account->email_blob(generic => {});
  my $mailbox = $account->create_mailbox;

  subtest "blobId" => sub {
    subtest "wrong form" => sub {
      my $res = $tester->request([[
        "Email/import" => {
          emails => {
            new => {
              blobId => ['foo'],
              mailboxIds => { $mailbox->id => JSON::true },
            },
          },
        },
      ]]);

      jcmp_deeply(
        $res->single_sentence('Email/import')->arguments->{notCreated},
        {
          new => {
            type => 'invalidProperties',
            properties => [ 'blobId' ],
          },
        },
        "got error about bad 'blobId'"
      ) or diag explain $res->as_stripped_triples;
    };

    subtest "bad blobId / not found" => sub {
      my $res = $tester->request([[
        "Email/import" => {
          emails => {
            new => {
              blobId => "foo",
              mailboxIds => { $mailbox->id => JSON::true },
            },
          },
        },
      ]]);

      jcmp_deeply(
        $res->single_sentence('Email/import')->arguments->{notCreated},
        {
          new => {
            type => 'invalidProperties',
            properties => [ 'blobId' ],
          },
        },
        "got error about bad 'blobId'"
      ) or diag explain $res->as_stripped_triples;
    };
  };

  subtest "receivedAt" => sub {
    subtest "wrong form" => sub {
      my $res = $tester->request([[
        "Email/import" => {
          emails => {
            new => {
              receivedAt => ['foo'],
              blobId     => $blob->blobId,
              mailboxIds => { $mailbox->id => JSON::true },
            },
          },
        },
      ]]);

      jcmp_deeply(
        $res->single_sentence('Email/import')->arguments->{notCreated},
        {
          new => {
            type => 'invalidProperties',
            properties => [ 'receivedAt' ],
          },
        },
        "got error about bad 'receivedAt'"
      ) or diag explain $res->as_stripped_triples;
    };

    subtest "bad receivedAt" => sub {
      my $res = $tester->request([[
        "Email/import" => {
          emails => {
            new => {
              receivedAt => "foo",
              blobId     => $blob->blobId,
              mailboxIds => { $mailbox->id => JSON::true },
            },
          },
        },
      ]]);

      jcmp_deeply(
        $res->single_sentence('Email/import')->arguments->{notCreated},
        {
          new => {
            type => 'invalidProperties',
            properties => [ 'receivedAt' ],
          },
        },
        "got error about bad 'receivedAt'"
      ) or diag explain $res->as_stripped_triples;
    };
  };

  subtest "mailboxIds" => sub {
    subtest "wrong form" => sub {
      my $res = $tester->request([[
        "Email/import" => {
          emails => {
            new => {
              mailboxIds => ['foo'],
              blobId     => $blob->blobId,
            },
          },
        },
      ]]);

      jcmp_deeply(
        $res->single_sentence('Email/import')->arguments->{notCreated},
        {
          new => {
            type => 'invalidProperties',
            properties => [ 'mailboxIds' ],
          },
        },
        "got error about bad 'mailboxIds'"
      ) or diag explain $res->as_stripped_triples;
    };

    subtest "bad mailboxIds" => sub {
      my $res = $tester->request([[
        "Email/import" => {
          emails => {
            new => {
              mailboxIds => "foo",
              blobId     => $blob->blobId,
            },
          },
        },
      ]]);

      jcmp_deeply(
        $res->single_sentence('Email/import')->arguments->{notCreated},
        {
          new => {
            type => 'invalidProperties',
            properties => [ 'mailboxIds' ],
          },
        },
        "got error about bad 'mailboxIds'"
      ) or diag explain $res->as_stripped_triples;
    };
  };

  subtest "keywords" => sub {
    subtest "wrong form" => sub {
      my $res = $tester->request([[
        "Email/import" => {
          emails => {
            new => {
              keywords => ['foo'],
              blobId     => $blob->blobId,
              mailboxIds => { $mailbox->id => JSON::true },
            },
          },
        },
      ]]);

      jcmp_deeply(
        $res->single_sentence('Email/import')->arguments->{notCreated},
        {
          new => {
            type => 'invalidProperties',
            properties => [ 'keywords' ],
          },
        },
        "got error about bad 'keywords'"
      ) or diag explain $res->as_stripped_triples;
    };

    subtest "bad keywords" => sub {
      my $res = $tester->request([[
        "Email/import" => {
          emails => {
            new => {
              keywords => "foo",
              blobId     => $blob->blobId,
              mailboxIds => { $mailbox->id => JSON::true },
            },
          },
        },
      ]]);

      jcmp_deeply(
        $res->single_sentence('Email/import')->arguments->{notCreated},
        {
          new => {
            type => 'invalidProperties',
            properties => [ 'keywords' ],
          },
        },
        "got error about bad 'keywords'"
      ) or diag explain $res->as_stripped_triples;
    };
  };

  subtest "EmailImport object -> required fields" => sub {
    my $res = $tester->request([[
      "Email/import" => {
        emails => {
          new => {},
        },
      },
    ]]);

    jcmp_deeply(
      $res->single_sentence('Email/import')->arguments->{notCreated},
      {
        new => {
          type => 'invalidProperties',
          properties => [ 'blobId', 'mailboxIds' ],
        },
      },
      "got error about missing required fields"
    ) or diag explain $res->as_stripped_triples;
  };
};
