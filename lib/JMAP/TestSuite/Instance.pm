# This will get a lot more complicated in the future. -- rjbs, 2016-11-07
package JMAP::TestSuite::Instance;
use Moose;

use JMAP::Tester;

has jmap_uri => (is => 'ro');
has download_uri => (is => 'ro');
has upload_uri => (is => 'ro');

sub simple_test {
  my ($self, $callback) = @_;
  my $tester = JMAP::Tester->new({
    jmap_uri => $self->jmap_uri,
  });

  $callback->($tester);
}

1;
