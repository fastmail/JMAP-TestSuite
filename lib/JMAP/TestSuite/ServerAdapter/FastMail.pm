package JMAP::TestSuite::ServerAdapter::FastMail;
use Moose;
with 'JMAP::TestSuite::ServerAdapter';

has base_uri => (
  is => 'ro',
  required => 1,
);

has accountId => (
  is => 'ro',
  required => 1,
);

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

  my ($credentials) = $self->credentials;

  return JMAP::TestSuite::Account::FastMail->new({
    server      => $self,
    accountId   => $self->accountId,
    credentials => $credentials,
  });
}

package JMAP::TestSuite::Account::FastMail {
  use Moose;
  with 'JMAP::TestSuite::Account';

  use Carp qw(croak);
  use JMAP::TestSuite::JMAP::Tester::Wrapper;
  use HTTP::Cookies;
  use LWP::UserAgent;
  use JSON qw(encode_json decode_json);
  use Data::Dumper;

  has lwp => (
    is => 'ro',
    isa => 'LWP::UserAgent',
    default => sub {
      LWP::UserAgent->new(cookie_jar => HTTP::Cookies->new);
    },
  );

  has credentials => (
    is  => 'ro',
    isa => 'HashRef',
    required => 1,
  );

  sub authenticated_tester {
    my ($self) = @_;

    # Start handshake
    my ($res, $json) = $self->auth_post({
      'username' => $self->credentials->{username},
    });
    unless ($res->is_success) {
      die "Failed to start login handshake: " . Dumper $res->as_string;
    }

    unless (grep {; $_->{type} eq 'password' } @{$json->{methods}}) {
      die "Can't use password login? " . Dumper $json;
    }

    my $lid = $json->{loginId};

    ($res, $json) = $self->auth_post({
      loginId  => $lid,
      type     => 'password',
      value    => $self->credentials->{password},
      remember => \0,
    });

    unless ($res->is_success) {
      die "Bad password, try again" . $res->as_string;
    }

    unless ($json->{sessionKey}) {
      die "Failed to login " . $res->as_string;
    }

    my $auth = "Bearer $json->{userId};$json->{sessionKey}";

    $self->lwp->default_header('authorization' => $auth);

    my $base = $self->server->base_uri =~ s{/\z}{}r;

    my $tester = JMAP::TestSuite::JMAP::Tester::Wrapper->new({
      api_uri => "$base/jmap/api/?u=$json->{userId}&jmap=1",
      ua      => $self->lwp,
      default_arguments => {
        accountId => $self->server->accountId,
      },
    });

    return $tester;
  }

  sub auth_post {
    my ($self, @args) = @_;

    my $res = $self->lwp->post(
      $self->server->authentication_uri,
      $self->jsonify_content(@args)
    );

    my $json = eval { decode_json($res->decoded_content) };
    $json //= {};

    return ($res, $json);
  }

  sub jsonify_content {
    my ($self, @args) = @_;

    # ->post(\%body) or ->post(\@body)
    if (ref $args[0]) {
      my @ret = (
        'Content-Type' => 'application/json; charset=utf-8',
        Accept         => 'application/json',
        Content        => encode_json($args[0]),
      );

      return @ret;
    }

    # ->post(%headers, Content => $body)
    for my $i (0..$#args) {
      if ($args[$i] eq 'Content') {
        croak "No content?!\n" unless $args[$i+1];
        $args[$i+1] = encode_json($args[$i+1]);
      }
    }

    unshift @args, (
      'Content-Type' => 'application/json; charset=utf-8',
      'Accept'       => 'application/json',
    );

    return @args;
  }

  no Moose;
  __PACKAGE__->meta->make_immutable;
}

no Moose;
__PACKAGE__->meta->make_immutable;
