package JMAP::TestSuite::Account;
use Moose;

use JMAP::Tester;

has jmap_uri     => (is => 'ro');
has download_uri => (is => 'ro');
has upload_uri   => (is => 'ro');

has test_instance => (is => 'ro', isa => 'Object', required => 1);

sub authenticated_tester {
  my $tester = JMAP::Tester->new({
    jmap_uri    => $_[0]->jmap_uri,
    upload_uri  => $_[0]->upload_uri,
  });
}

1;
