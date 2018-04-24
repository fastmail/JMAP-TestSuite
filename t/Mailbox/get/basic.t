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

pristine_test "Mailbox/get with no existing entities" => sub {
  my ($self) = @_;

  plan skip_all => "Cyrus requires at least one mailbox"
    if $self->server->isa('JMAP::TestSuite::ServerAdapter::Cyrus');

  my $tester = $self->tester;

  subtest "No arguments" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/get" => {},
      ]],
    });
    ok($res->is_success, "Mailbox/get")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/get")->arguments,
      superhashof({
        accountId => jstr($self->context->accountId),
        state     => jstr(),
        list      => [],
        notFound  => [],
      }),
      "No mailboxes looks good",
    );
  };
};

pristine_test "Mailbox/get when some entities exist" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $mailbox1 = $self->context->create_mailbox;

  my $mailbox2 = $self->context->create_mailbox;

  # Standard /get method. The ids argument may be null to fetch all at once.

  for my $test (
    [ "No arguments" => {}, ],
    [ "null ids"     => { ids => undef }, ],
  ) {
    my ($name, $args) = @$test;

    subtest "$name" => sub {
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Mailbox/get" => $args,
        ]],
      });
      ok($res->is_success, "Mailbox/get")
        or diag explain $res->http_response->as_string;

      jcmp_deeply(
        $res->single_sentence("Mailbox/get")->arguments,
        superhashof({
          accountId => jstr($self->context->accountId),
          state     => jstr(),
          notFound  => [],
        }),
        "Base response looks good",
      );

      my @found = grep {;
        $_->{id} eq $mailbox1->id
      } @{ $res->single_sentence("Mailbox/get")->arguments->{list} };

      is(@found, 1, 'found our mailbox');

      jcmp_deeply(
        $found[0],
        superhashof({
          id           => jstr($mailbox1->id),
          name         => jstr($mailbox1->name),
          parentId     => undef, # XXX - May be decided by server?
          role         => undef,
          sortOrder    => jnum(),
          totalEmails  => jnum(0),
          unreadEmails => jnum(0),
          totalEmails  => jnum(0),
          unreadEmails => jnum(0),
          myRights     => superhashof({
            map {
              $_ => jbool(),
            } qw(
              mayReadItems
              mayAddItems
              mayRemoveItems
              maySetSeen
              maySetKeywords
              mayCreateChild
              mayRename
              mayDelete
              maySubmit
            )
          }),
        }),
        "Our mailbox looks good"
      ) or diag explain $res->as_stripped_triples;
    };
  }

  subtest "Limit by id" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/get" => { ids => [ $mailbox1->id ], },
      ]],
    });
    ok($res->is_success, "Mailbox/get")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/get")->arguments,
      superhashof({
        accountId => jstr($self->context->accountId),
        state     => jstr(),
        notFound  => [],
      }),
      "Base response looks good",
    ) or diag explain $res->as_stripped_triples;

    my @found = @{ $res->single_sentence("Mailbox/get")->arguments->{list} };

    is(@found, 1, 'got only 1 mailbox');

    jcmp_deeply(
      $found[0],
      superhashof({
        id           => jstr($mailbox1->id),
        name         => jstr($mailbox1->name),
        parentId     => undef, # XXX - May be decided by server?
        role         => undef,
        sortOrder    => jnum(),
        totalEmails  => jnum(0),
        unreadEmails => jnum(0),
        totalEmails  => jnum(0),
        unreadEmails => jnum(0),
        myRights     => superhashof({
          map {
            $_ => jbool(),
          } qw(
            mayReadItems
            mayAddItems
            mayRemoveItems
            maySetSeen
            maySetKeywords
            mayCreateChild
            mayRename
            mayDelete
            maySubmit
          )
        }),
      }),
      "Our mailbox looks good"
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "Limit to no ids" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/get" => { ids => [ ], },
      ]],
    });
    ok($res->is_success, "Mailbox/get")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/get")->arguments,
      superhashof({
        accountId => jstr($self->context->accountId),
        state     => jstr(),
        list      => [],
        notFound  => [],
      }),
      "Base response looks good, has no mailboxes",
    ) or diag explain $res->as_stripped_triples;
  };
};

test "Mailbox/get with limiting properties in resposne" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $mailbox1 = $self->context->create_mailbox;

  subtest "properties => null gives us all properties" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/get" => {
          ids        => [ $mailbox1->id ],
          properties => undef,
        },
      ]],
    });
    ok($res->is_success, "Mailbox/get")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/get")->arguments,
      superhashof({
        accountId => jstr($self->context->accountId),
        state     => jstr(),
        notFound  => [],
      }),
      "Base response looks good",
    ) or diag explain $res->as_stripped_triples;

    my @found = @{ $res->single_sentence("Mailbox/get")->arguments->{list} };

    is(@found, 1, 'got only 1 mailbox');

    jcmp_deeply(
      $found[0],
      superhashof({
        id           => jstr($mailbox1->id),
        name         => jstr($mailbox1->name),
        parentId     => undef, # XXX - May be decided by server?
        role         => undef,
        sortOrder    => jnum(),
        totalEmails  => jnum(0),
        unreadEmails => jnum(0),
        totalEmails  => jnum(0),
        unreadEmails => jnum(0),
        myRights     => superhashof({
          map {
            $_ => jbool(),
          } qw(
            mayReadItems
            mayAddItems
            mayRemoveItems
            maySetSeen
            maySetKeywords
            mayCreateChild
            mayRename
            mayDelete
            maySubmit
          )
        }),
      }),
      "Our mailbox looks good"
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "Limiting to a few properties works and includes id" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/get" => {
          ids        => [ $mailbox1->id ],
          properties => [ 'name', 'sortOrder' ],
        },
      ]],
    });
    ok($res->is_success, "Mailbox/get")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/get")->arguments,
      superhashof({
        accountId => jstr($self->context->accountId),
        state     => jstr(),
        notFound  => [],
      }),
      "Base response looks good",
    ) or diag explain $res->as_stripped_triples;

    my @found = @{ $res->single_sentence("Mailbox/get")->arguments->{list} };

    is(@found, 1, 'got only 1 mailbox');

    jcmp_deeply(
      $found[0],
      {
        id           => jstr($mailbox1->id),
        name         => jstr($mailbox1->name),
        sortOrder    => jnum(),
      },
      "Our mailbox looks good"
    ) or diag explain $res->as_stripped_triples;
  };
};

run_me;
done_testing;
