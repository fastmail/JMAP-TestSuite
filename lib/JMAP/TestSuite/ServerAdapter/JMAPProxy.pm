package JMAP::TestSuite::ServerAdapter::JMAPProxy;
use Moose;
with 'JMAP::TestSuite::ServerAdapter';

has base_uri => (
  is => 'ro',
  required => 1,
);

has accountIds => (
  isa => 'ArrayRef[Str]',
  traits  => [ 'Array' ],
  handles => { accountIds => 'elements' },
  required => 1,
);

sub any_account {
  my ($self) = @_;

  my $base = $self->base_uri =~ s{/\z}{}r;

  my ($accountId) = $self->accountIds;

  return JMAP::TestSuite::Account::JMAPProxy->new({
    server    => $self,
    accountId => $accountId,

    api_uri       => "$base/jmap/$accountId",
    download_uri  => "$base/raw/$accountId",
    upload_uri    => "$base/upload/$accountId",
  });
}

package JMAP::TestSuite::Account::JMAPProxy {
  use Moose;
  with 'JMAP::TestSuite::Account';

  use JMAP::TestSuite::JMAP::Tester::Wrapper;

  has api_uri      => (is => 'ro');
  has download_uri => (is => 'ro');
  has upload_uri   => (is => 'ro');

  sub authenticated_tester {
    my $tester = JMAP::TestSuite::JMAP::Tester::Wrapper->new({
      api_uri     => $_[0]->api_uri,
      upload_uri  => $_[0]->upload_uri,
    });

    $tester->ua->ssl_opts(verify_hostname => 0);
    $tester->ua->ssl_opts(SSL_verify_mode => 0x00);

    $tester;
  }

  no Moose;
  __PACKAGE__->meta->make_immutable;
}

no Moose;
__PACKAGE__->meta->make_immutable;
