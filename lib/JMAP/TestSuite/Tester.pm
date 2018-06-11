use strict;
use warnings;
package JMAP::TestSuite::Tester;
use Test::Routine 0.025;

use JMAP::TestSuite;
use JMAP::TestSuite::Util;
use Test::More;
use Test::Deep ':v1';
use Test::Deep::JType;

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

sub should_skip_test {
  my ($self, $test) = @_;

  if (
       JMAP::TestSuite::Util::is_pristine($test->description)
    && ! $self->server->can('pristine_account')
  ) {
    return 1;
  }

  return;
}

before run_test => sub {
  my ($self, $test) = @_;

  # If we can't provide a pristine account and the test requires it, perform
  # no other actions
  return if $self->should_skip_test($test);

  # Give us a fresh context every time
  $self->_clear_context;

  if (JMAP::TestSuite::Util::is_pristine($test->description)) {
    # XXX - Ick. -- alh, 2018-02-21
    $self->_set_context(
      $self->server->pristine_account->context,
    );
  }
};

around run_test => sub {
  my ($orig, $self, $test, @rest) = @_;

  if ($self->should_skip_test($test)) {
    my $desc = $test->description;

    Test::Abortable::subtest($desc, sub {
      plan skip_all => "Test requires pristine account, none available";
    });

    return;
  }

  $self->$orig($test, @rest);
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
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "$call" => $args,
      ]],
    });
    ok($res->is_success, "$call")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("$call")->arguments,
      superhashof({
        accountId => jstr($self->context->accountId),
        state     => jstr(),
        total     => jnum,
        position  => jnum(0),
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
