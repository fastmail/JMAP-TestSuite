package JMAP::TestSuite::ServerAdapter::Cyrus;
use Moose;
with 'JMAP::TestSuite::ServerAdapter';

has base_uri => (
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

  my ($credentials) = $self->credentials;

  # Is it okay to require the credentials to have the accountId?  If we don't
  # do that, we need to make accounts' accountId only be known on demand.  Or
  # we could authenticate eagerly on Simple accounts.  For now, I'll do the
  # simplest thing I've thought of: this. -- rjbs, 2016-11-18
  # ^^ This comment stolen from the Simple account.
  return JMAP::TestSuite::Account::Cyrus->new({
    server      => $self,
    accountId   => $credentials->{accountId},
    credentials => $credentials,
  });
}

package JMAP::TestSuite::Account::Cyrus {
  use Moose;
  with 'JMAP::TestSuite::Account';

  use JMAP::Tester;
  use MIME::Base64 ();

  sub authenticated_tester {
    my ($self) = @_;

    my $base = $self->base_uri =~ s{/\z}{}r;

    my $tester = JMAP::Tester->new({
      jmap_uri   => "$base/jmap",
      upload_uri => "$base/upload",
      download_uri => "$base/download",
    });

    my $auth = join q{:}, @{ $self->credentials }{ qw(username password) };

    $tester->ua->default_header(
      Authorization => MIME::Base64::encode_base64($auth, ''),
    );

    return $tester;
  }

  no Moose;
  __PACKAGE__->meta->make_immutable;
}

no Moose;
__PACKAGE__->meta->make_immutable;
