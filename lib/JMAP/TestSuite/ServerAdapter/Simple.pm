package JMAP::TestSuite::ServerAdapter::Simple;
use Moose;
with 'JMAP::TestSuite::ServerAdapter';

has authentication_uri => (
  is => 'ro',
  required => 1,
);

has credentials => (
  isa => 'ArrayRef[HashRef]',
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
  return JMAP::TestSuite::Account::Simple->new({
    server      => $self,
    accountId   => $credentials->{accountId},
    credentials => $credentials,
  });
}

package JMAP::TestSuite::Account::Simple {
  use Moose;
  with 'JMAP::TestSuite::Account';

  use JMAP::Tester;

  sub authenticated_tester {
    my ($self) = @_;

    my $tester = JMAP::Tester->new({
      authentication_uri => $self->server->authentication_uri,
    });

    my $auth = $tester->simple_auth(
      $self->credentials->{username},
      $self->credentials->{password},
    );

    Carp::confess("can't authenticate with JMAP credentials")
      unless $auth->is_success;

    return $tester;
  }

  no Moose;
  __PACKAGE__->meta->make_immutable;
}

no Moose;
__PACKAGE__->meta->make_immutable;
