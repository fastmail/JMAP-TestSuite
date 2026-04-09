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
    server    => $self,
    accountId => $accountId,
    api_uri       => "$base/jmap/$accountId",
    download_uri  => "$base/raw/{accountId}/{blobId}/{name}",
    upload_uri    => "$base/upload/$accountId",
  });
}

sub any_account {
  my ($self) = @_;
  my ($accountId) = $self->accountIds;
  return $self->_make_account($accountId);
}

sub pristine_account {
  my ($self) = @_;

  my $num = $USERNUM++;
  my $user = "jt-$STARTTIME-$$-$num";

  my $sep = $self->cyrus_hierarchy_separator;
  my $folder = "user$sep$user";

  # 1. Create Cyrus user via IMAP admin
  my $client = $self->imap_client;
  die "Failed to create user" unless $client->create($folder);
  die "Failed to setacl" unless $client->setacl($folder, $user, "lrswipkxtecdan");

  # 2. Tell the proxy about the new account via management API
  my $mgmt = $self->mgmt_uri =~ s{/\z}{}r;
  my $content = encode_json({
    accountid  => $user,
    type       => 'imap',
    username   => $user,
    password   => $self->cyrus_password,
    imapHost   => $self->cyrus_host,
    imapPort   => $self->cyrus_port,
    imapSSL    => 1,
    caldavURL  => $self->cyrus_http_url,
    carddavURL => $self->cyrus_http_url,
  });
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

  has api_uri      => (is => 'ro');
  has download_uri => (is => 'ro');
  has upload_uri   => (is => 'ro');

  sub authenticated_tester {
    my $tester = JMAP::TestSuite::JMAP::Tester::WithSugar->new({
      api_uri      => $_[0]->api_uri,
      upload_uri   => $_[0]->upload_uri,
      download_uri => $_[0]->download_uri,
    });

    $tester->ua->lwp->ssl_opts(verify_hostname => 0);
    $tester->ua->lwp->ssl_opts(SSL_verify_mode => 0x00);

    $tester;
  }

  no Moose;
  __PACKAGE__->meta->make_immutable;
}

no Moose;
__PACKAGE__->meta->make_immutable;
