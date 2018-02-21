package JMAP::TestSuite::ServerAdapter::Cyrus;
use Moose;
with 'JMAP::TestSuite::ServerAdapter';

use Process::Status;
use Data::GUID qw(guid_string);

has base_uri => (
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

  my ($credentials) = $self->credentials;

  # Is it okay to require the credentials to have the accountId?  If we don't
  # do that, we need to make accounts' accountId only be known on demand.  Or
  # we could authenticate eagerly on Simple accounts.  For now, I'll do the
  # simplest thing I've thought of: this. -- rjbs, 2016-11-18
  # ^^ This comment stolen from the Simple account.
  return JMAP::TestSuite::Account::Cyrus->new({
    server      => $self,
    accountId   => $credentials->{username},
    credentials => $credentials,
  });
}

sub pristine_account {
  my ($self) = @_;

  # XXX - Do something far less janky. -- alh, 2018-02-21
  my $user = "jt-" . guid_string();

  my $res = `echo 'mypassword' | saslpasswd2 -p -c $user`;
  my $ps = Process::Status->new;

  unless ($ps->is_success) {
    die "Failed to create sasl auth for new user. Got output: $res\n";
  }

  $res = `echo 'createmailbox user/$user\@localhost' | /usr/cyrus/bin/cyradm -u imapuser -w secret localhost`;
  $ps = Process::Status->new;

  unless ($ps->is_success) {
    die "Failed to create a new account in cyrus. Got output: $res\n";
  }

  my $username = "$user\@localhost";

  return JMAP::TestSuite::Account::Cyrus->new({
    server      => $self,
    accountId   => $username,
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
