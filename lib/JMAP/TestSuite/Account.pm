package JMAP::TestSuite::Account;
use Moose;

use JMAP::Tester;

has accountId    => (is => 'ro', required => 1);

has jmap_uri     => (is => 'ro');
has download_uri => (is => 'ro');
has upload_uri   => (is => 'ro');

has test_instance => (is => 'ro', isa => 'Object', required => 1);

sub authenticated_tester {
  my $tester = JMAP::Tester->new({
    jmap_uri    => $_[0]->jmap_uri,
    upload_uri  => $_[0]->upload_uri,
  });
}

sub context { JMAP::TestSuite::Account::Context->new({ account => $_[0] }) }

package JMAP::TestSuite::Account::Context {
  use Moose;

  has account => (
    is => 'ro',
    handles  => [ qw(accountId) ],
    required => 1
  );

  has tester  => (
    is   => 'ro',
    lazy => 1,
    default => sub { $_[0]->account->authenticated_tester },
  );

  for my $method (qw(create create_list create_batch)) {
    my $code = sub {
      my ($self, $moniker, $to_pass, $to_munge) = @_;
      my $class = "JMAP::TestSuite::Entity::\u$moniker";
      $class->$method($to_pass, {
        $to_munge ? %$to_munge : (),
        context => $self,
      });
    };
    no strict 'refs';
    *$method = $code;
  }

  sub import_messages {
    my ($self, $to_pass, $to_munge) = @_;
    JMAP::TestSuite::Entity::Message->import_messages(
      $to_pass,
      { ($to_munge ? %$to_munge : ()), context => $self },
    );
  }

  no Moose;
  __PACKAGE__->meta->make_immutable;
}

no Moose;
__PACKAGE__->meta->make_immutable;
