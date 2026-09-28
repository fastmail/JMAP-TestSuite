package JMAP::TestSuite::ServerAdapter::JMAPProxy;
use Moose;
with 'JMAP::TestSuite::ServerAdapter';

use Data::GUID qw(guid_string);
use LWP::UserAgent;
use Mail::IMAPClient;
use JSON qw(encode_json decode_json);

our $STARTTIME = time();
our $USERNUM = 1;

has base_uri => (
  is => 'ro',
  required => 1,
);

has mgmt_uri => (
  is => 'ro',
  required => 1,
);

has accountIds => (
  isa => 'ArrayRef[Str]',
  traits  => [ 'Array' ],
  handles => { accountIds => 'elements' },
  required => 1,
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
  default => 'admin',
);

has cyrus_admin_pass => (
  is => 'ro',
  default => 'secret',
);

has cyrus_admin_use_ssl => (
  is => 'ro',
  default => 0,
);

has cyrus_hierarchy_separator => (
  is => 'ro',
  default => '/',
);

has _detected_separator => (
  is      => 'ro',
  lazy    => 1,
  default => sub {
    my ($self) = @_;
    my $ns = eval { $self->imap_client->namespace() };
    return $ns->[0][0][1] if $ns && $ns->[0] && $ns->[0][0] && $ns->[0][0][1];
    return $self->cyrus_hierarchy_separator;
  },
);

# Set in test-config.json when the proxy's backend is Cyrus; makes
# isa('JMAP::TestSuite::ServerAdapter::Cyrus') true so the suite's
# Cyrus-specific TODO blocks apply.
has cyrus_backend => (
  is      => 'ro',
  default => 0,
);

around 'isa' => sub {
  my ($orig, $self, $class) = @_;
  return 1 if $class eq 'JMAP::TestSuite::ServerAdapter::Cyrus'
            && ref($self)
            && $self->can('cyrus_backend')
            && $self->cyrus_backend;
  return $self->$orig($class);
};

# JMAPProxy-specific: password for IMAP user accounts (not admin)
has cyrus_password => (
  is => 'ro',
  default => 'password',
);

# JMAPProxy-specific: CalDAV/CardDAV URL for proxy config
has cyrus_http_url => (
  is => 'ro',
  default => 'http://localhost:8080',
);

# Create pristine accounts as JMAP passthrough accounts against Cyrus's native
# JMAP (restart-test-proxy.sh --jmap sets this).
has passthrough => (
  is      => 'ro',
  default => 0,
);

has imap_client => (
  is  => 'ro',
  isa => 'Mail::IMAPClient',
  lazy => 1,
  default => sub {
    my ($self) = @_;

    Mail::IMAPClient->new(
      Server   => $self->cyrus_host,
      Port     => $self->cyrus_port,
      Ssl      => $self->cyrus_admin_use_ssl ? 1 : 0,

      User     => $self->cyrus_admin_user,
      Password => $self->cyrus_admin_pass,
      Uid      => 1,
    ) or die "Failed to connect to cyrus imap: $@\n";
  },
);

sub _make_account {
  my ($self, $accountId) = @_;
  my $base = $self->base_uri =~ s{/\z}{}r;
  return JMAP::TestSuite::Account::JMAPProxy->new({
    server             => $self,
    accountId          => $accountId,
    authentication_uri => "$base/session",
  });
}

sub any_account {
  my ($self) = @_;
  my ($accountId) = $self->accountIds;
  return $self->_make_account($accountId);
}

sub pristine_account {
  my ($self) = @_;
  return $self->_create_pristine_account();
}

sub pool_account_pair {
  my ($self) = @_;
  my $acct_a = $self->_create_pristine_account();
  my $acct_b = $self->_create_pristine_account(poolid => $acct_a->accountId);
  return ($acct_a, $acct_b);
}

# A primary and a delegated account registered under one upstream login with
# different backendAccountIds.  Sharing a cred_fingerprint is what lets the
# proxy forward a copy between them natively.
sub same_creds_account_pair {
  my ($self) = @_;
  die "same_creds_account_pair requires passthrough mode\n" unless $self->passthrough;

  my $num     = $USERNUM++;
  my $primary = "jt-$STARTTIME-$$-$num-p";
  my $shared  = "jt-$STARTTIME-$$-$num-s";
  my $sep     = $self->_detected_separator;

  my $client = $self->imap_client;
  for my $u ($primary, $shared) {
    die "Failed to create user $u\n" unless $client->create("user$sep$u");
    die "Failed to setacl for $u\n"
      unless $client->setacl("user$sep$u", $u, "lrswipkxtecdan");
  }
  # Delegating to the primary puts both accountIds in its upstream session.
  die "Failed to delegate $shared to $primary\n"
    unless $client->setacl("user$sep$shared", $primary, "lrswipkxtecdan");

  my $mgmt = $self->mgmt_uri =~ s{/\z}{}r;
  my $lwp  = LWP::UserAgent->new;
  for my $spec ([$primary, undef], [$shared, $shared]) {
    my ($aid, $backend) = @$spec;
    my $res = $lwp->post("$mgmt/api/accounts",
      Content_Type => 'application/json',
      Content => encode_json({
        accountid  => $aid,
        sessionUrl => $self->cyrus_http_url . "/jmap",
        username   => $primary,          # SAME login for both
        password   => $self->cyrus_password,
        authType   => 'basic',
        poolid     => $primary,
        ($backend ? (backendAccountId => $backend) : ()),
      }));
    die "Failed to register $aid: " . $res->status_line . "\n"
      unless $res->is_success;
  }

  return ($self->_make_account($primary), $self->_make_account($shared));
}

# One passthrough account and one IMAP account in the same pool, for copies
# that must cross backend types (always orchestrated, never native-forwarded).
sub mixed_account_pair {
  my ($self) = @_;
  die "mixed_account_pair requires passthrough mode\n" unless $self->passthrough;

  my $a = $self->_create_pristine_account();   # passthrough

  my $num  = $USERNUM++;
  my $b    = "jt-$STARTTIME-$$-$num-imap";
  my $sep  = $self->_detected_separator;
  my $client = $self->imap_client;
  die "Failed to create user $b\n" unless $client->create("user$sep$b");
  die "Failed to setacl for $b\n"
    unless $client->setacl("user$sep$b", $b, "lrswipkxtecdan");

  my $mgmt = $self->mgmt_uri =~ s{/\z}{}r;
  my $res  = LWP::UserAgent->new->post("$mgmt/api/accounts",
    Content_Type => 'application/json',
    Content => encode_json({
      accountid  => $b,
      type       => 'imap',
      username   => $b,
      password   => $self->cyrus_password,
      imapHost   => $self->cyrus_host,
      imapPort   => $self->cyrus_port,
      imapSSL    => 1,   # matches _create_pristine_account
      caldavURL  => $self->cyrus_http_url,
      carddavURL => $self->cyrus_http_url,
      poolid     => $a->accountId,
    }));
  die "Failed to register IMAP account $b: " . $res->status_line . "\n"
    unless $res->is_success;

  return ($a, $self->_make_account($b));
}

sub _create_pristine_account {
  my ($self, %extra) = @_;

  my $num = $USERNUM++;
  my $user = "jt-$STARTTIME-$$-$num";

  my $sep = $self->_detected_separator;
  my $folder = "user$sep$user";

  # 1. Create Cyrus user via IMAP admin
  my $client = $self->imap_client;
  die "Failed to create user" unless $client->create($folder);
  die "Failed to setacl" unless $client->setacl($folder, $user, "lrswipkxtecdan");

  # 2. Tell the proxy about the new account via management API
  my $mgmt = $self->mgmt_uri =~ s{/\z}{}r;
  my $content;
  if ($self->passthrough) {
    $content = encode_json({
      accountid  => $user,
      sessionUrl => $self->cyrus_http_url . "/jmap",
      username   => $user,
      password   => $self->cyrus_password,
      authType   => 'basic',
      %extra,
    });
  }
  else {
    $content = encode_json({
      accountid  => $user,
      type       => 'imap',
      username   => $user,
      password   => $self->cyrus_password,
      imapHost   => $self->cyrus_host,
      imapPort   => $self->cyrus_port,
      imapSSL    => 1,
      caldavURL  => $self->cyrus_http_url,
      carddavURL => $self->cyrus_http_url,
      %extra,
    });
  }
  my $lwp = LWP::UserAgent->new();
  my $res = $lwp->post("$mgmt/api/accounts",
   Content_Type => 'application/json',
   Content => $content
  );
  die "Failed to create proxy account for $user: " . $res->status_line . "\n"
    unless $res->is_success;

  return $self->_make_account($user);
}

package JMAP::TestSuite::Account::JMAPProxy {
  use Moose;
  with 'JMAP::TestSuite::Account';

  use JMAP::TestSuite::JMAP::Tester::WithSugar;
  use MIME::Base64 qw(encode_base64);

  has authentication_uri => (is => 'ro', required => 1);

  sub authenticated_tester {
    my ($self) = @_;
    my $tester = JMAP::TestSuite::JMAP::Tester::WithSugar->new({
      authentication_uri => $self->authentication_uri,
    });

    my $accountId = $self->accountId;
    my $password  = $self->server->cyrus_password;
    my $creds     = encode_base64("$accountId:$password", '');
    $tester->ua->lwp->default_header(Authorization => "Basic $creds");
    $tester->ua->lwp->ssl_opts(verify_hostname => 0);
    $tester->ua->lwp->ssl_opts(SSL_verify_mode => 0x00);

    my $auth = $tester->update_client_session;
    my $session = $auth->client_session;
    my @using = sort keys %{ $session->{capabilities} // {} };
    $tester->default_using(\@using) if @using;

    $tester;
  }

  no Moose;
  __PACKAGE__->meta->make_immutable;
}

no Moose;
__PACKAGE__->meta->make_immutable;
