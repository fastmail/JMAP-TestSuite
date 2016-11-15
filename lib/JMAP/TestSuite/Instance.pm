# This will get a lot more complicated in the future. -- rjbs, 2016-11-07
package JMAP::TestSuite::Instance;
use Moose;

use JMAP::Tester;

has jmap_uri     => (is => 'ro');
has download_uri => (is => 'ro');
has upload_uri   => (is => 'ro');

sub any_account {
  require JMAP::TestSuite::Account;
  return JMAP::TestSuite::Account->new({
    test_instance => $_[0],
    map {; $_ => $_[0]->$_ } qw( jmap_uri download_uri upload_uri )
  });
}

sub simple_test {
  my ($self, $callback) = @_;

  my $account = $self->any_account;
  my $tester  = $account->authenticated_tester;

  $callback->($account, $tester);
}

1;
