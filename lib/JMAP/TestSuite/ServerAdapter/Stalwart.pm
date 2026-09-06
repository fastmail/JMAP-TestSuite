package JMAP::TestSuite::ServerAdapter::Stalwart;
use Moose;
with 'JMAP::TestSuite::ServerAdapter';

use HTTP::Request;
use LWP::UserAgent;
use JSON qw(encode_json decode_json);
use MIME::Base64 qw(encode_base64);

our $STARTTIME = time();
our $USERNUM   = 1;

# The Stalwart HTTP base (e.g. http://localhost:8090)
has base_uri    => (is => 'ro', required => 1);
has admin_user  => (is => 'ro', required => 1);
has admin_pass  => (is => 'ro', required => 1);
has test_domain => (is => 'ro', required => 1);

has _admin_account_id => (
  is      => 'ro',
  lazy    => 1,
  default => sub {
    my ($self) = @_;
    my $base   = $self->base_uri =~ s{/\z}{}r;
    my $creds  = encode_base64($self->admin_user . ':' . $self->admin_pass, '');
    my $lwp    = LWP::UserAgent->new;
    $lwp->default_header(Authorization => "Basic $creds");
    my $res = $lwp->get("$base/jmap/session");
    die "Failed to fetch Stalwart admin session: " . $res->status_line . "\n"
      unless $res->is_success;
    my $session = decode_json($res->decoded_content);
    my $primary = $session->{primaryAccounts}
      or die "No primaryAccounts in Stalwart admin session\n";
    my ($account_id) = values %$primary;
    die "No account ID in Stalwart admin session primaryAccounts\n"
      unless defined $account_id;
    return $account_id;
  },
);

has _domain_id => (
  is      => 'ro',
  lazy    => 1,
  default => sub {
    my ($self) = @_;
    my $base   = $self->base_uri =~ s{/\z}{}r;
    my $creds  = encode_base64($self->admin_user . ':' . $self->admin_pass, '');
    my $lwp    = LWP::UserAgent->new;
    $lwp->default_header(Authorization => "Basic $creds");

    my $req = HTTP::Request->new(POST => "$base/jmap");
    $req->header('Content-Type' => 'application/json');
    $req->content(encode_json({
      using       => ['urn:stalwart:jmap'],
      methodCalls => [
        [ 'x:Domain/query', {
            accountId => $self->_admin_account_id,
            filter    => { name => $self->test_domain },
          }, 'R1'
        ],
      ],
    }));
    my $res = $lwp->request($req);
    die "Failed to query Stalwart domain: " . $res->status_line . "\n"
      unless $res->is_success;
    my $data = decode_json($res->decoded_content);
    my $result = $data->{methodResponses}[0];
    die "Unexpected method response querying domain\n"
      unless $result && $result->[0] eq 'x:Domain/query';
    my $ids = $result->[1]{ids}
      or die "No domain IDs returned for " . $self->test_domain . "\n";
    die "Domain " . $self->test_domain . " not found on Stalwart server\n"
      unless @$ids;
    return $ids->[0];
  },
);

sub any_account {
  my ($self) = @_;
  return $self->_create_pristine_account;
}

sub pristine_account {
  my ($self) = @_;
  return $self->_create_pristine_account;
}

sub _create_pristine_account {
  my ($self) = @_;

  my $num  = $USERNUM++;
  my $name = "jt-$STARTTIME-$$-$num";
  my $pass = join('-', map { sprintf('%08x', int(rand(0xFFFFFFFF))) } 1..4);

  my $base   = $self->base_uri =~ s{/\z}{}r;
  my $creds  = encode_base64($self->admin_user . ':' . $self->admin_pass, '');
  my $lwp    = LWP::UserAgent->new;
  $lwp->default_header(Authorization => "Basic $creds");

  my $req = HTTP::Request->new(POST => "$base/jmap");
  $req->header('Content-Type' => 'application/json');
  $req->content(encode_json({
    using       => ['urn:stalwart:jmap'],
    methodCalls => [
      [ 'x:Account/set', {
          accountId => $self->_admin_account_id,
          create    => {
            new1 => {
              '@type'      => 'User',
              name         => $name,
              domainId     => $self->_domain_id,
              credentials  => {
                '0' => { '@type' => 'Password', secret => $pass },
              },
              roles        => { '@type' => 'User' },
            },
          },
        }, 'R1'
      ],
    ],
  }));
  my $res = $lwp->request($req);
  die "Failed to create Stalwart user $name: " . $res->status_line . "\n"
    unless $res->is_success;

  my $data = decode_json($res->decoded_content);
  my $result = $data->{methodResponses}[0];
  die "Unexpected method response creating account\n"
    unless $result && $result->[0] eq 'x:Account/set';
  my $created = $result->[1]{created}{new1};
  die "Failed to create account $name: " . encode_json($result->[1]{notCreated} // {}) . "\n"
    unless $created;

  # The created id is not the JMAP accountId; read that from the user's own
  # session.
  my $user_creds = encode_base64("$name\@" . $self->test_domain . ":$pass", '');
  my $user_lwp   = LWP::UserAgent->new;
  $user_lwp->default_header(Authorization => "Basic $user_creds");
  my $sess_res = $user_lwp->get("$base/jmap/session");
  die "Failed to fetch Stalwart session for $name: " . $sess_res->status_line . "\n"
    unless $sess_res->is_success;
  my $session    = decode_json($sess_res->decoded_content);
  my $primary    = $session->{primaryAccounts}
    or die "No primaryAccounts in session for $name\n";
  my ($account_id) = values %$primary;
  die "No account ID in session for $name\n" unless defined $account_id;

  return JMAP::TestSuite::Account::Stalwart->new({
    server    => $self,
    accountId => $account_id,
    username  => "$name\@" . $self->test_domain,
    password  => $pass,
  });
}

package JMAP::TestSuite::Account::Stalwart {
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

    # Take only the capabilities from the session; its URLs carry Stalwart's
    # internal container hostname, so build them from base_uri instead.
    my $lwp = LWP::UserAgent->new;
    $lwp->default_header(Authorization => "Basic $creds");
    my $sess_res = $lwp->get("$base/jmap/session");
    die "Failed to fetch Stalwart session for $user: " . $sess_res->status_line . "\n"
      unless $sess_res->is_success;
    my $session = decode_json($sess_res->decoded_content);

    my @using = sort keys %{ $session->{capabilities} // {} };

    my $account_id   = $self->accountId;
    my $api_uri      = "$base/jmap";
    my $upload_uri   = "$base/jmap/upload/$account_id/";
    my $download_uri = "$base/jmap/download/{accountId}/{blobId}/{name}";

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
