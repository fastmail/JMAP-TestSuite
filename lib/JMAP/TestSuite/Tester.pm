use strict;
use warnings;
package JMAP::TestSuite::Tester;
use Test::Routine 0.025;

use JMAP::TestSuite;
use JMAP::TestSuite::Util;
use Test::More;

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

1;
