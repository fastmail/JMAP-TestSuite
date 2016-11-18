package JMAP::TestSuite::Account {
  use Moose::Role;

  use JMAP::Tester;

  has accountId => (is => 'ro', required => 1);
  has server    => (is => 'ro', isa => 'Object', required => 1);

  requires 'authenticated_tester';

  sub context { JMAP::TestSuite::AccountContext->new({ account => $_[0] }) }

  no Moose::Role;
}

package JMAP::TestSuite::AccountContext {
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

  for my $method (qw(create create_list create_batch retrieve retrieve_batch)) {
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

1;
