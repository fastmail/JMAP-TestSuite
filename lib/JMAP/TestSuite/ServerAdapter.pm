package JMAP::TestSuite::ServerAdapter;
use Moose::Role;

use Hash::Util::FieldHash qw(fieldhash);
use JMAP::Tester;
use Scope::Guard ();

requires 'any_account';

has _locks => (
  is    => 'rw',
  lazy  => 1,
  init_arg  => undef,
  default   => sub {
    fieldhash my %hash;
    return \%hash;
  },
);

sub unshared_account {
  my ($self) = @_;
  return $self->pristine_account if $self->can('pristine_account');

  my $account 	= $self->any_account;

  my $accountId = $account->accountId;
  my $guard = Scope::Guard->new(sub { warn "releasing lock for $accountId" });

  $self->_locks->{ $account } = $guard;

  return $account;
}

no Moose::Role;
1;
