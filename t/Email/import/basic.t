use strict;
use warnings;
use Test::Routine;
use Test::Routine::Util;

with 'JMAP::TestSuite::Tester';

use JMAP::TestSuite::Util qw(batch_ok pristine_test);

use Test::Deep ':v1';
use Test::Deep::JType;
use Test::More;
use JSON qw(decode_json);
use JSON::Typist;
use Test::Abortable;

test "Email/import with bad values" => sub {
  my ($self) = @_;

  my $tester = $self->tester;
  my $context = $self->context;

  subtest "emails -> wrong form" => sub {
    for my $bad (undef, "none", ["foo"]) {
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Email/import" => {
            emails => $bad,
          },
        ]],
      });

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
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/import" => {},
      ]],
    });

    jcmp_deeply(
      $res->single_sentence('error')->arguments,
      {
        type => 'invalidArguments',
        arguments => [ 'emails' ], # XXX - Not to spec, but cyrus gives it
      },
      "got error about bad 'emails'"
    ) or diag explain $res->as_stripped_triples;
  };

  my $blob = $context->email_blob(generic => {});
  my $mailbox = $context->create_mailbox;

  subtest "blobId" => sub {
    subtest "wrong form" => sub {
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Email/import" => {
            emails => {
              new => {
                blobId => ['foo'],
                mailboxIds => { $mailbox->id => JSON::true },
              },
            },
          },
        ]],
      });

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
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Email/import" => {
            emails => {
              new => {
                blobId => "foo",
                mailboxIds => { $mailbox->id => JSON::true },
              },
            },
          },
        ]],
      });

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
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Email/import" => {
            emails => {
              new => {
                receivedAt => ['foo'],
                blobId     => $blob->blobId,
                mailboxIds => { $mailbox->id => JSON::true },
              },
            },
          },
        ]],
      });

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
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Email/import" => {
            emails => {
              new => {
                receivedAt => "foo",
                blobId     => $blob->blobId,
                mailboxIds => { $mailbox->id => JSON::true },
              },
            },
          },
        ]],
      });

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
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Email/import" => {
            emails => {
              new => {
                mailboxIds => ['foo'],
                blobId     => $blob->blobId,
              },
            },
          },
        ]],
      });

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
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Email/import" => {
            emails => {
              new => {
                mailboxIds => "foo",
                blobId     => $blob->blobId,
              },
            },
          },
        ]],
      });

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
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Email/import" => {
            emails => {
              new => {
                keywords => ['foo'],
                blobId     => $blob->blobId,
                mailboxIds => { $mailbox->id => JSON::true },
              },
            },
          },
        ]],
      });

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
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Email/import" => {
            emails => {
              new => {
                keywords => "foo",
                blobId     => $blob->blobId,
                mailboxIds => { $mailbox->id => JSON::true },
              },
            },
          },
        ]],
      });

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
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/import" => {
          emails => {
            new => {},
          },
        },
      ]],
    });

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

test "good imports" => sub {
  my ($self) = @_;

  my $tester = $self->tester;
  my $context = $self->context;

  my $mailbox = $context->create_mailbox;
  my $mailbox2 = $context->create_mailbox;

  subtest "single mailbox import, all values" => sub {
    my $blob = $context->email_blob(generic => {});

    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
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
      ]],
    });

    jcmp_deeply(
      $res->single_sentence('Email/import')->arguments,
      {
        accountId  => jstr($self->context->accountId),
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

    # XXX - Verify it made it to the mailbox?    
    # XXX - Verify keywords/utcdate
  };

  subtest "single mailbox import, default values" => sub {
    my $blob = $context->email_blob(generic => {});

    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/import" => {
          emails => {
            new => {
              blobId => $blob->blobId,
              mailboxIds => { $mailbox->id => JSON::true },
            },
          },
        },
      ]],
    });

    jcmp_deeply(
      $res->single_sentence('Email/import')->arguments,
      {
        accountId  => jstr($self->context->accountId),
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

    # XXX - Verify it made it to the mailbox?    
    # XXX - Verify keywords/utcdate

  };

  subtest "multiple mailboxes" => sub {
    my $blob = $context->email_blob(generic => {});

    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
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
      ]],
    });

    jcmp_deeply(
      $res->single_sentence('Email/import')->arguments,
      {
        accountId  => jstr($self->context->accountId),
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

    # XXX - Confirm
  };
};

test "one import fails, another succeeds" => sub {
  my ($self) = @_;

  my $tester = $self->tester;
  my $context = $self->context;

  my $mailbox = $context->create_mailbox;

  my $blob = $context->email_blob(generic => {});
  my $blob2 = $context->email_blob(generic => {});

  my $res = $tester->request({
    using => [ "ietf:jmapmail" ],
    methodCalls => [[
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
    ]],
  });

  jcmp_deeply(
    $res->single_sentence('Email/import')->arguments,
    {
      accountId  => jstr($self->context->accountId),
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

  # XXX - Verify it made it to the mailbox?    
  # XXX - Verify keywords/utcdate
};

test "invalidEmail" => sub {
  my ($self) = @_;

  my $tester = $self->tester;
  my $context = $self->context;

  my $mailbox = $context->create_mailbox;
  my $blob = $tester->upload('text/plain', \"some data");

  my $res = $tester->request({
    using => [ "ietf:jmapmail" ],
    methodCalls => [[
      "Email/import" => {
        emails => {
          new => {
            blobId     => $blob->blobId,
            mailboxIds => { $mailbox->id => JSON::true },
          },
        },
      },
    ]],
  });

  TODO: {
    todo_skip "Need to figure out what to do here", 1;
    ok(1);
  };

};

run_me;
done_testing;
