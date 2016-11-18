package JMAP::TestSuite::ServerAdapter::Simple;
use Moose;
with 'JMAP::TestSuite::ServerAdapter';

has authentication_uri => (
  is => 'ro',
  required => 1,
);

has credentials => (
  isa => 'ArrayRef[Str]',
  traits  => [ 'Array' ],
  handles => { credentials => 'elements' },
  required => 1,
);

sub any_account {
  my ($self) = @_;

  my $base = $self->base_uri =~ s{/\z}{}r;

  my ($accountId) = $self->accountIds;

  return JMAP::TestSuite::Account::JMAPProxy->new({
    server    => $self,
    accountId => $accountId,

    jmap_uri      => "$base/jmap/$accountId",
    download_uri  => "$base/raw/$accountId",
    upload_uri    => "$base/upload/$accountId",
  });
}

package JMAP::TestSuite::Account::JMAPProxy {
  use Moose;
  with 'JMAP::TestSuite::Account';

  use JMAP::Tester;

  has jmap_uri     => (is => 'ro');
  has download_uri => (is => 'ro');
  has upload_uri   => (is => 'ro');

  sub authenticated_tester {
    my $tester = JMAP::Tester->new({
      jmap_uri    => $_[0]->jmap_uri,
      upload_uri  => $_[0]->upload_uri,
    });
  }

  no Moose;
  __PACKAGE__->meta->make_immutable;
}

no Moose;
__PACKAGE__->meta->make_immutable;
