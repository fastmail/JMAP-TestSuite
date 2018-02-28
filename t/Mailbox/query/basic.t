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

# XXX - Need test for cancalc

pristine_test "Mailbox/query with no existing entities" => sub {
  my ($self) = @_;

  plan skip_all => "Cyrus requires at least one mailbox"
    if $self->server->isa('JMAP::TestSuite::ServerAdapter::Cyrus');

  my $tester = $self->tester;

  subtest "No arguments" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/query" => {},
      ]],
    });
    ok($res->is_success, "Mailbox/query")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/query")->arguments,
      superhashof({
        accountId => jstr($self->context->accountId),
        state     => jstr(),
        position  => jnum(0),
        total     => jnum(0),
        ids       => [],
        canCalculateChanges => jbool(),
      }),
      "No mailboxes looks good",
    ) or diag explain $res->as_stripped_triples;
  };
};

# XXX - Test for basic response

pristine_test "Mailbox/query filtering with filterConditions" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $mailbox1 = $self->context->create_mailbox({
    name => "A simple mailbox",
  });

  my $mailbox2 = $self->context->create_mailbox({
    name     => "A simple mailbox",
    parentId => $mailbox1->id,
  });

  subtest "parentId" => sub {

    subtest "does not have a parentId" => sub {
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Mailbox/query" => {
            filter => {
              parentId => undef,
            },
          },
        ]],
      });
      ok($res->is_success, "Mailbox/query")
        or diag explain $res->http_response->as_string;

      my $ids = $res->single_sentence("Mailbox/query")->arguments->{ids};

      jcmp_deeply($ids, supersetof($mailbox1->id), 'Got top-level mailbox');
      jcmp_deeply($ids, noneof($mailbox2->id), 'Did not get sub-mailbox');
    };

    subtest "has a parentId" => sub {
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Mailbox/query" => {
            filter => {
              parentId => $mailbox1->id,
            },
          },
        ]],
      });
      ok($res->is_success, "Mailbox/query")
        or diag explain $res->http_response->as_string;

      my $ids = $res->single_sentence("Mailbox/query")->arguments->{ids};

      jcmp_deeply($ids, [ $mailbox2->id ], 'Got our one child mailbox');
    };
  };

  subtest "hasRole" => sub {
    # Find some mailboxes with roles
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/get" => {},
      ]],
    });

    my @with_roles = map {;
      $_->{id}
    } grep {;
      $_->{role}
    } @{ $res->single_sentence("Mailbox/get")->arguments->{list} };

    plan skip_all => "No mailboxes with roles found, can't continue"
      unless @with_roles;

    subtest "false" => sub {
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Mailbox/query" => {
            filter => {
              hasRole => JSON::false,
            },
          },
        ]],
      });
      ok($res->is_success, "Mailbox/query")
        or diag explain $res->http_response->as_string;

      my $ids = $res->single_sentence("Mailbox/query")->arguments->{ids};

      jcmp_deeply(
        $ids,
        supersetof($mailbox1->id, $mailbox2->id),
        'Got mailboxes with no roles',
      );

      jcmp_deeply(
        $ids,
        noneof(@with_roles),
        'Did not get mailboxes with roles',
      ) or diag explain $ids;
    };

    subtest "true" => sub {
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Mailbox/query" => {
            filter => {
              hasRole => JSON::true,
            },
          },
        ]],
      });
      ok($res->is_success, "Mailbox/query")
        or diag explain $res->http_response->as_string;

      my $ids = $res->single_sentence("Mailbox/query")->arguments->{ids};

      jcmp_deeply($ids, \@with_roles, 'Got mailboxes with roles only');
    };
  };
};

# XXX - sort, position, anchor, achorOffset, limit

run_me;
done_testing;
