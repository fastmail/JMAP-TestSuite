package JMAP::TestSuite::ServerAdapter::Cyrus;
use Moose;
with 'JMAP::TestSuite::ServerAdapter';

use Process::Status;
use Data::GUID qw(guid_string);

has base_uri => (
  is => 'ro',
  required => 1,
);

has saslpasswd2_path => (
  is => 'ro',
  default => 'saslpasswd2',
);

has no_sasl => (
  is => 'ro',
);

has cyrus_prefix => (
  is      => 'ro',
  default => '/usr/cyrus/',
);

has cyrus_host => (
  is => 'ro',
  default => 'localhost',
);

has cyrus_port => (
  is => 'ro',
);

has cyrus_admin_user => (
  is => 'ro',
  default => 'imapuser',
);

has cyrus_admin_pass => (
  is => 'ro',
  default => 'secret',
);

has cyrus_hierarchy_separator => (
  is => 'ro',
  default => '/',
);

has credentials => (
  isa => 'ArrayRef[HashRef]',
  traits  => [ 'Array' ],
  handles => { credentials => 'elements' },
  required => 1,
);

sub any_account {
  my ($self) = @_;

  my ($credentials) = $self->credentials;

  # Is it okay to require the credentials to have the accountId?  If we don't
  # do that, we need to make accounts' accountId only be known on demand.  Or
  # we could authenticate eagerly on Simple accounts.  For now, I'll do the
  # simplest thing I've thought of: this. -- rjbs, 2016-11-18
  # ^^ This comment stolen from the Simple account.
  my $account_id = $credentials->{username};
  $account_id =~ s/@.*//;

  return JMAP::TestSuite::Account::Cyrus->new({
    server      => $self,
    accountId   => $account_id,
    credentials => $credentials,
  });
}

sub pristine_account {
  my ($self) = @_;

  # XXX - Do something far less janky. -- alh, 2018-02-21
  # These must be lowercase or cyrus can't auth them
  my $user = "jt-" . lc guid_string();

  unless ($self->no_sasl) {
    my $sasl = $self->saslpasswd2_path;

    my $res = `echo 'mypassword' | $sasl -p -c $user 2>&1`;
    my $ps = Process::Status->new;

    unless ($ps->is_success) {
      die "Failed to create sasl auth for new user. Got output: $res\n";
    }
  }

  my $cyradm = $self->cyrus_prefix . "/bin/cyradm";

  my $host = $self->cyrus_host;
  my $port = $self->cyrus_port ? "--port " . $self->cyrus_port : "";
  my $cyr_user = $self->cyrus_admin_user;
  my $cyr_pass = $self->cyrus_admin_pass;
  my $sep = $self->cyrus_hierarchy_separator;

  my $cmd = "echo 'createmailbox user$sep$user\@localhost' \\
             | /usr/cyrus/bin/cyradm --notls -u $cyr_user -w $cyr_pass $host $port";

  my $res = `$cmd 2>&1`;
  unless ($res =~ /^\s*[^\s]+>\s*[^\s]+>\s*$/) {
    die "Failed to run $cmd: $res\n";
  }

  my $ps = Process::Status->new;

  unless ($ps->is_success) {
    die "Failed to create a new account in cyrus. Got output: $res\n";
  }

  my $username = "$user\@localhost";

  return JMAP::TestSuite::Account::Cyrus->new({
    server      => $self,
    accountId   => $user,
    credentials => {
      username => $username,
      password => 'mypassword',
    },
  });
}

package JMAP::TestSuite::Account::Cyrus {
  use Moose;
  with 'JMAP::TestSuite::Account';

  use JMAP::Tester;
  use MIME::Base64 ();

  has credentials => (is => 'ro', required => 1);

  sub authenticated_tester {
    my ($self) = @_;

    my $base = $self->server->base_uri =~ s{/\z}{}r;

    my $tester = JMAP::Tester->new({
      api_uri    => "$base/jmap/",
      upload_uri => "$base/jmap/upload/" . $self->credentials->{username} . "/",
      download_uri => "$base/jmap/download/{accountId}/{blobId}/{name}/",
    });

    my $auth = join q{:}, @{ $self->credentials }{ qw(username password) };

    $tester->ua->default_header(
      Authorization => 'Basic ' . MIME::Base64::encode_base64($auth, ''),
    );

    return $tester;
  }

  no Moose;
  __PACKAGE__->meta->make_immutable;
}

no Moose;
__PACKAGE__->meta->make_immutable;
