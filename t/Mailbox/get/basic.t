use strict;
use warnings;
use Test::Routine;
use Test::Routine::Util;

with 'JMAP::TestSuite::Tester';

use JMAP::TestSuite::Util qw(batch_ok mailbox);

use Test::Deep ':v1';
use Test::Deep::JType;
use Test::More;
use JSON qw(decode_json);
use JSON::Typist;
use Test::Abortable;

# Can't have existing data so must be pristine
test "Mailbox/get with no existing entities" => { requires_pristine => 1 } => sub {
  my ($self) = @_;

  plan skip_all => "Cyrus requires at least one mailbox"
    if $self->server->isa('JMAP::TestSuite::ServerAdapter::Cyrus');

  my $tester = $self->tester;

  subtest "No arguments" => sub {
    my $res = $tester->request([[
      "Mailbox/get" => {},
    ]]);
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

# Can't have existing data so must be pristine
test "Mailbox/get when some entities exist" => { requires_pristine => 1 } => sub {
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
      my $res = $tester->request([[
        "Mailbox/get" => $args,
      ]]);
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
        mailbox({
          id            => jstr($mailbox1->id),
          name          => jstr($mailbox1->name),
          totalEmails   => jnum(0),
          unreadEmails  => jnum(0),
          totalThreads  => jnum(0),
          unreadThreads => jnum(0),
        }),
        "Our mailbox looks good"
      ) or diag explain $res->as_stripped_triples;
    };
  }

  subtest "Limit by id" => sub {
    my $res = $tester->request([[
      "Mailbox/get" => { ids => [ $mailbox1->id ], },
    ]]);
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
      mailbox({
        id            => jstr($mailbox1->id),
        name          => jstr($mailbox1->name),
        totalEmails   => jnum(0),
        unreadEmails  => jnum(0),
        totalThreads  => jnum(0),
        unreadThreads => jnum(0),
      }),
      "Our mailbox looks good"
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "Limit to no ids" => sub {
    my $res = $tester->request([[
      "Mailbox/get" => { ids => [ ], },
    ]]);
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
    my $res = $tester->request([[
      "Mailbox/get" => {
        ids        => [ $mailbox1->id ],
        properties => undef,
      },
    ]]);
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
      mailbox({
        id            => jstr($mailbox1->id),
        name          => jstr($mailbox1->name),
        totalEmails   => jnum(0),
        unreadEmails  => jnum(0),
        totalThreads  => jnum(0),
        unreadThreads => jnum(0),
      }),
      "Our mailbox looks good"
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "Limiting to a few properties works and includes id" => sub {
    my $res = $tester->request([[
      "Mailbox/get" => {
        ids        => [ $mailbox1->id ],
        properties => [ 'name', 'sortOrder' ],
      },
    ]]);
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
