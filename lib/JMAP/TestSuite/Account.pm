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

  use JMAP::TestSuite::Util qw(batch_ok);
  use Test::More;
  use Email::MessageID;

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

  sub email_blob {
    my ($self, $which, $arg) = @_;

    Carp::confess("don't know how to generate test message named $which")
      unless $which && $which eq 'generic';

    require Email::MIME;
    my $email = Email::MIME->create(
      header_str => [
        From => 'example@example.com',
        To   => 'example@example.biz',
        Subject => $arg->{subject} || 'This is a test',
        'Message-Id' =>    $arg->{message_id}
                        // Email::MessageID->new->in_brackets,
        ( $arg->{headers} ? @{ $arg->{headers} } : () ),
      ],
      body => $arg->{body} // "This is a very simple message.",
    );

    return $self->tester->upload('message/rfc822', \$email->as_string);
  }

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

  for my $method (qw(get_state)) {
    my $code = sub {
      my ($self, $moniker) = @_;
      my $class = "JMAP::TestSuite::Entity::\u$moniker";
      $class->$method({ context => $self });
    };
    no strict 'refs';
    *$method = $code;
  }

  my $inc = 0;

  sub create_mailbox {
    # XXX - This should probably not use Test::* functions and
    #       instead hard fail if something goes wrong.
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ($self, $arg) = @_;

    $arg ||= {};
    $arg->{name} ||= "Folder $inc at $^T.$$";
    $inc++;

    my $batch = $self->create_batch(mailbox => {
      x => $arg,
    });

    batch_ok($batch);

    ok($batch->is_entirely_successful, "created a mailbox");

    my $x = $batch->result_for('x');

    return $x;
  }

  sub add_message_to_mailboxes {
    JMAP::TestSuite::Entity::Email->add_message_to_mailboxes(@_);
  }

  sub import_messages {
    my ($self, $to_pass, $to_munge) = @_;
    JMAP::TestSuite::Entity::Email->import_messages(
      $to_pass,
      { ($to_munge ? %$to_munge : ()), context => $self },
    );
  }

  no Moose;
  __PACKAGE__->meta->make_immutable;
}

1;
