package JMAP::TestSuite::ServerAdapter::CyrusDirect;
use Moose;
with 'JMAP::TestSuite::ServerAdapter';

use LWP::UserAgent;
use JSON qw(encode_json decode_json);

our $STARTTIME = time();
our $USERNUM   = 1;

# The Cyrus HTTP base (e.g. http://localhost:8080)
has base_uri => (is => 'ro', required => 1);

# The Cyrus admin management API (e.g. http://localhost:8001)
has mgmt_uri => (is => 'ro', required => 1);

has cyrus_host     => (is => 'ro', default => 'localhost');
has cyrus_port     => (is => 'ro');
has cyrus_password => (is => 'ro', default => 'password');

has cyrus_admin_user => (is => 'ro', default => 'admin');
has cyrus_admin_pass => (is => 'ro', default => 'admin');

has cyrus_quota_kb => (is => 'ro', default => 102400);

has accountIds => (
  isa     => 'ArrayRef[Str]',
  traits  => ['Array'],
  handles => { accountIds => 'elements' },
  required => 1,
);

# Always behave as a Cyrus adapter so Cyrus-specific TODO blocks apply.
around 'isa' => sub {
  my ($orig, $self, $class) = @_;
  return 1 if $class eq 'JMAP::TestSuite::ServerAdapter::Cyrus' && ref($self);
  return $self->$orig($class);
};

sub _make_account {
  my ($self, $username) = @_;
  return JMAP::TestSuite::Account::CyrusDirect->new({
    server   => $self,
    accountId => $username,
    username => $username,
    password => $self->cyrus_password,
  });
}

sub any_account {
  my ($self) = @_;
  my ($accountId) = $self->accountIds;
  return $self->_make_account($accountId);
}

sub pristine_account {
  my ($self) = @_;
  return $self->_create_pristine_account;
}

sub pool_account_pair {
  my ($self) = @_;
  my $from = $self->_create_pristine_account;
  my $to   = $self->_create_pristine_account;
  # Each account needs rights on the other to see it in its JMAP session.
  $self->_imap_setacl($from->username, $to->username);
  $self->_imap_setacl($to->username, $from->username);
  return ($from, $to);
}

sub _imap_setacl {
  my ($self, $owner, $grantee) = @_;
  require Mail::IMAPTalk;
  my $imap = Mail::IMAPTalk->new(
    Server   => $self->cyrus_host,
    Port     => $self->cyrus_port,
    Username => $self->cyrus_admin_user,
    Password => $self->cyrus_admin_pass,
    UseSSL   => 0,
  ) or die "Cannot connect to IMAP admin: $@\n";
  $imap->setacl("user/$owner", $grantee, 'lrswipkxtecdan')
    or die "setacl user/$owner -> $grantee failed: "
         . ($imap->get_last_error // '?') . "\n";
  $imap->logout;
}

sub _create_pristine_account {
  my ($self) = @_;

  my $num  = $USERNUM++;
  my $user = "jt-$STARTTIME-$$-$num";

  my $mgmt = $self->mgmt_uri =~ s{/\z}{}r;
  my $lwp  = LWP::UserAgent->new;
  my $res  = $lwp->request(
    do {
      my $req = HTTP::Request->new(PUT => "$mgmt/api/$user");
      $req->header('Content-Type' => 'application/json');
      $req->content(encode_json({
        mailboxes => [{ name => 'INBOX', subscribed => \1 }],
        quota_kb  => $self->cyrus_quota_kb,
      }));
      $req;
    }
  );
  die "Failed to create Cyrus user $user: " . $res->status_line . "\n"
    unless $res->is_success;

  return $self->_make_account($user);
}

package JMAP::TestSuite::Account::CyrusDirect {
  use Moose;
  with 'JMAP::TestSuite::Account';

  use MIME::Base64 qw(encode_base64);
  use LWP::UserAgent;
  use JSON qw(decode_json);
  use JMAP::TestSuite::JMAP::Tester::WithSugar;

  has username => (is => 'ro', required => 1);
  has password => (is => 'ro', required => 1);

  sub authenticated_tester {
    my ($self) = @_;

    my $base  = $self->server->base_uri =~ s{/\z}{}r;
    my $user  = $self->username;
    my $pass  = $self->password;
    my $creds = encode_base64("$user:$pass", '');

    # Cyrus rejects a "using" it did not advertise, so build default_using
    # from the session.
    my $lwp = LWP::UserAgent->new;
    $lwp->default_header(Authorization => "Basic $creds");
    my $sess_res = $lwp->get("$base/jmap");
    die "Failed to fetch Cyrus session: " . $sess_res->status_line . "\n"
      unless $sess_res->is_success;
    my $session = decode_json($sess_res->decoded_content);

    # Top-level capabilities only; an accountCapabilities key in "using" is
    # unknownCapability.
    my @using = sort keys %{ $session->{capabilities} // {} };

    my $api_uri      = $session->{apiUrl}      // "/jmap/";
    my $upload_uri   = $session->{uploadUrl}   // "/jmap/upload/$user/";
    my $download_uri = $session->{downloadUrl} // "/jmap/download/{accountId}/{blobId}/{name}/";

    for ($api_uri, $upload_uri, $download_uri) {
      s{^/}{$base/} unless m{^https?://};
    }

    # Cyrus appends ?accept={type}; drop it rather than expand it.
    $download_uri =~ s/[?&][^?&]*\{type\}[^?&]*//;

    my $tester = JMAP::TestSuite::JMAP::Tester::WithSugar->new({
      api_uri      => $api_uri,
      upload_uri   => $upload_uri,
      download_uri => $download_uri,
    });

    $tester->ua->set_default_header(Authorization => "Basic $creds");
    $tester->default_using(\@using);

    return $tester;
  }

  no Moose;
  __PACKAGE__->meta->make_immutable;
}

no Moose;
__PACKAGE__->meta->make_immutable;
