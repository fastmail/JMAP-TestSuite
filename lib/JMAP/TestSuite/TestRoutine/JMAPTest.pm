use strict;
use warnings;

package JMAP::TestSuite::TestRoutine::JMAPTest;

use Moose::Role;

has requires_pristine => (is => 'ro', default => 0);

sub skip_reason {
  my ($self, $test_instance) = @_;

  return unless $self->requires_pristine;

  # This should really be governed by a role on adapters, like
  # CanProvidePristineAccount. -- rjbs, 2018-07-15

  return if $test_instance->server->can('pristine_account');
  return "test requires pristine_account";
}

no Moose::Role;
1;
