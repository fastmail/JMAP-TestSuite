use strict;
use warnings;
package JMAP::TestSuite::Tester;

use Test::Routine 0.025;
use Test::More;

if ($ENV{JMTS_TELEMETRY}) {
  $ENV{JMAP_TESTER_LOGGER} = 'HTTP:-2'; # STDERR
}

if ($ENV{JMTS_TEST_OUTPUT_TO_STDERR}) {
  Test::More->builder->output(*STDERR);
}

use JMAP::TestSuite;
use JMAP::TestSuite::TestRoutine::JMAPTest;
use JMAP::TestSuite::Util;
use Test::Deep ':v1';
use Test::Deep::JType;

sub test_routine_test_traits {
  'JMAP::TestSuite::TestRoutine::JMAPTest'
}

has server => (
  is      => 'ro',
  does    => 'JMAP::TestSuite::ServerAdapter',
  default => sub {
    JMAP::TestSuite->get_server;
  },
);

has context => (
  is      => 'ro',
  lazy    => 1,
  clearer => '_clear_context',
  default => sub {
    shift->server->any_account->context
  },
  writer  => '_set_context',
  handles => [qw(
    tester
  )],
);

before run_test => sub {
  my ($self, $test) = @_;

  # Give us a fresh context every time
  $self->_clear_context;

  if ($test->requires_pristine) {
    # XXX - Ick. -- alh, 2018-02-21
    $self->_set_context(
      $self->server->pristine_account->context,
    );
  }
};

sub test_query {
  my ($self, $call, $args, $expect, $describer_sub, $test) = @_;

  my $tester = $self->tester;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  # sort/limit tests don't want to know about server-provided folders
  unless ($args->{filter}) {
    $args->{filter}{hasRole} = JSON::false;
  }

  subtest "$test" => sub {
    my $res = $tester->request([[
      "$call" => $args,
    ]]);
    ok($res->is_success, "$call")
      or diag explain $res->http_response->as_string;

    is($res->sentence(0)->name, $call, "Got $call response")
      or diag explain $res->as_stripped_triples;

    jcmp_deeply(
      $res->single_sentence("$call")->arguments,
      superhashof({
        accountId  => jstr($self->context->accountId),
        queryState => jstr(),
        total      => jnum,
        position   => jnum(0),
        canCalculateChanges => jbool(),
        %$expect, # can override position
      }),
      "sorted as expected",
    ) or $self->explain_test_query_failure(
      $res,
      $call,
      $expect->{ids},
      $describer_sub,
    );
  };
}

sub explain_test_query_failure {
  my ($self, $res, $call, $expect, $describer_sub) = @_;

  my $got = $res->single_sentence("$call")->arguments->{ids};

  my @got_names = map {; $describer_sub->($self, $_) } @$got;
  my @exp_names = map {; $describer_sub->($self, $_) } @$expect;

  note("Got:    @got_names");
  note("Wanted: @exp_names");
}

1;
