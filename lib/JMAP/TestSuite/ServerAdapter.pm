package JMAP::TestSuite::ServerAdapter;
use Moose::Role;

use JMAP::Tester;

requires 'any_account';

sub simple_test {
  my ($self, $callback) = @_;

  $callback->($self->any_account->context);
}

no Moose::Role;
1;
