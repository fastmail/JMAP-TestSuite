package JMAP::TestSuite::Account {
  use Moose::Role;

  use Email::MessageID;
  use JMAP::Tester;
  use JMAP::TestSuite::Util qw(batch_ok);
  use Scalar::Util qw(blessed);
  use Test::More;
  use List::Util qw(pairkeys);

  has accountId => (is => 'ro', required => 1);
  has server    => (is => 'ro', isa => 'Object', required => 1);

  requires 'authenticated_tester';

  has tester  => (
    is   => 'ro',
    does  => 'JMAP::TestSuite::JMAP::Tester::WithSugarRole',
    lazy => 1,
    default => sub { $_[0]->authenticated_tester },
    clearer => 'clear_tester',
  );

  my %types = (
    generic => sub {
      my ($self, $arg) = @_;

      my %default_headers = (
        From => $arg->{from} // 'example@example.com',
        To   => $arg->{to} // 'example@example.biz',
        Subject => $arg->{subject} // 'This is a test',
        'Message-Id' =>    $arg->{message_id}
                        // Email::MessageID->new->in_brackets,
      );

      if ($arg->{raw_headers}) {
        delete $default_headers{$_} for pairkeys @{ $arg->{raw_headers} };
      }

      my @default_headers = map {;
        $_ => $default_headers{$_}
      } grep {
        exists $default_headers{$_}
      } qw(From To Subject Message-Id);

      require Email::MIME;
      return Email::MIME->create(
        ( $arg->{raw_headers} ? ( header => $arg->{raw_headers} ) : () ),
        header_str => [
          @default_headers,
          ( $arg->{headers} ? @{ $arg->{headers} } : () ),
        ],
        (
          $arg->{body_str} ? ( body_str => $arg->{body_str} ) :
          $arg->{body}     ? ( body     => $arg->{body}     ) :
                             ( body => "This is a very simple message." )
        ),
        attributes => $arg->{attributes} // {},
      );
    },
    with_attachment => sub {
      my ($self, $arg) = @_;

      my %default_headers = (
        From => $arg->{from} // 'example@example.com',
        To   => $arg->{to} // 'example@example.biz',
        Subject => $arg->{subject} // 'This is a test',
        'Message-Id' =>    $arg->{message_id}
                        // Email::MessageID->new->in_brackets,
      );

      if ($arg->{raw_headers}) {
        delete $default_headers{$_} for pairkeys @{ $arg->{raw_headers} };
      }

      my @default_headers = map {;
        $_ => $default_headers{$_}
      } grep {
        exists $default_headers{$_}
      } qw(From To Subject Message-Id);

      require Email::MIME;
      return Email::MIME->create(
        attributes => $arg->{attributes} // {},
        ( $arg->{raw_headers} ? ( header => $arg->{raw_headers} ) : () ),
        header_str => [
          %default_headers,
          ( $arg->{headers} ? @{ $arg->{headers} } : () ),
        ],
        parts => [
          "Main body",
          Email::MIME->create(
            attributes => {
              content_type => "text/plain",
              disposition  => "attachment",
              charset      => "US-ASCII",
              encoding     => "quoted-printable",
              filename     => "attached.txt",
              name         => "attached.txt",
            },
            body_str => "Hello there!",
          ),
        ],
      );
    },
    provided => sub {
      my ($self, $arg) = @_;

      unless ($arg->{email}) {
        Carp::confese("'provided' email_type requires an 'email' argument!");
      }

      unless ($arg->{dont_modify}) {
        my $obj = blessed($arg->{email})
                    ? $arg->{email}
                    : Email::MIME->new($arg->{email});

        # Message needs to be unqiue for cyrus within an account
        $obj->header_str_set(
          'X-JMTS-Unique' => Email::MessageID->new->in_brackets,
        );

        return $obj->as_string;
      }

      return $arg->{email};
    },
  );

  sub email_blob {
    my ($self, $which, $arg) = @_;

    Carp::confess("don't know how to generate test message named $which")
      unless my $gen = $types{$which};

    my $email = $gen->($self, $arg);

    return $self->tester->upload({
      accountId => $self->accountId,
      type      => 'message/rfc822',
      blob      => blessed($email) ? \$email->as_string : \$email,
    });
  }

  for my $method (qw(create create_list create_batch retrieve retrieve_batch)) {
    my $code = sub {
      my ($self, $moniker, $to_pass, $to_munge) = @_;
      my $class = "JMAP::TestSuite::Entity::\u$moniker";
      $class->$method($to_pass, {
        $to_munge ? %$to_munge : (),
        account => $self,
      });
    };
    no strict 'refs';
    *$method = $code;
  }

  for my $method (qw(get_state)) {
    my $code = sub {
      my ($self, $moniker) = @_;
      my $class = "JMAP::TestSuite::Entity::\u$moniker";
      $class->$method({ account => $self });
    };
    no strict 'refs';
    *$method = $code;
  }

  my $mb_inc = 0;

  sub create_mailbox {
    # XXX - This should probably not use Test::* functions and
    #       instead hard fail if something goes wrong.
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ($self, $arg) = @_;

    $arg ||= {};
    $arg->{name} ||= "Folder $mb_inc at $^T.$$";
    $mb_inc++;

    my $batch = $self->create_batch(mailbox => {
      x => $arg,
    });

    batch_ok($batch);

    ok($batch->is_entirely_successful, "created a mailbox")
      or diag explain $batch->all_results;

    my $x = $batch->result_for('x');

    if ($ENV{JMTS_TELEMETRY}) {
      my $extra = '';

      if ($x->parentId) {
        $extra = " with parentId " . $x->parentId;
      }

      note(
          "Account " . $self->accountId
        . " Created mailbox '" . $x->name . "' id (" . $x->id . ")$extra"
      );
    }

    return $x;
  }

  sub add_message_to_mailboxes {
    JMAP::TestSuite::Entity::Email->add_message_to_mailboxes(@_);
  }

  sub import_messages {
    my ($self, $to_pass, $to_munge) = @_;
    JMAP::TestSuite::Entity::Email->import_messages(
      $to_pass,
      { ($to_munge ? %$to_munge : ()), account => $self },
    );
  }

  my $cal_inc = 0;

  sub create_calendar {
    # XXX - This should probably not use Test::* functions and
    #       instead hard fail if something goes wrong.
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ($self, $arg) = @_;

    $arg ||= {};
    $arg->{name} ||= "Calendar $cal_inc at $^T.$$";
    $arg->{color} ||= '#ffffff';
    $cal_inc++;

    my $batch = $self->create_batch(calendar => {
      x => $arg,
    });

    batch_ok($batch);

    ok($batch->is_entirely_successful, "created a calendar")
      or diag explain $batch->all_results;

    my $x = $batch->result_for('x');

    if ($ENV{JMTS_TELEMETRY}) {
      note(
          "Account " . $self->accountId
        . " Created calendar '" . $x->name . "' id (" . $x->id . ")"
      );
    }

    return $x;
  }

  no Moose::Role;
}

1;
