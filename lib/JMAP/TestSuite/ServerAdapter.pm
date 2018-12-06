package JMAP::TestSuite::ServerAdapter;
use Moose::Role;

use Digest::MD5 qw(md5_hex);
use Fcntl qw(LOCK_EX LOCK_UN);
use Hash::Util::FieldHash qw(fieldhash);
use JMAP::Tester;
use JMAP::Tester::Abort qw(abort);
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

has use_websockets => (
  is => 'ro',
  isa => 'Bool',
  default => sub { $ENV{JMTS_USE_WEBSOCKETS} || 0 },
);

sub can_use_websockets { 0 }

sub BUILD {
  my ($self) = @_;

  if ($self->use_websockets && ! $self->can_use_websockets) {
    my $what = ref($self);
    die "Cannot build $what: use_websockets requested but $what does not support it\n";
  }
}

has lock_dir => (
  is  => 'ro',
  isa => 'Str',
  default => sub {
    "account-locks";
  },
);

sub wait_for_lock {
  my ($self, $account_id) = @_;

  my $lock_dir = $self->lock_dir;

  abort("can't lock, lock directory does not exist") unless -d "account-locks";

  my $path = $self->lock_dir . q{/} . md5_hex($account_id);
  open my $fh, '>>', $path or Carp::confess("can't open $path to flock: $!");
  flock $fh, LOCK_EX;

  return Scope::Guard->new(sub {
    flock $fh, LOCK_UN;
  });
}

sub unshared_account {
  my ($self) = @_;
  return $self->pristine_account if $self->can('pristine_account');

  my $account 	= $self->any_account;
  my $accountId = $account->accountId;

  $self->_locks->{ $account } = $self->wait_for_lock($accountId);

  return $account;
}

no Moose::Role;
1;
