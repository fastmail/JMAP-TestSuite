package JMAP::TestSuite::Account {
  use Moose::Role;

  use Email::MessageID;
  use JMAP::Tester;
  use JMAP::TestSuite::Util qw(batch_ok);
  use Scalar::Util qw(blessed);
  use Test::More;
  use List::Util qw(pairkeys);
  use feature qw(state);

  has accountId => (is => 'ro', required => 1);
  has server    => (is => 'ro', isa => 'Object', required => 1);

  requires 'authenticated_tester';

  # Every standard method except Core/echo requires accountId, so the tester
  # sends this account's id unless the test passes accountId => \undef.
  has tester  => (
    is   => 'ro',
    does  => 'JMAP::TestSuite::JMAP::Tester::WithSugarRole',
    lazy => 1,
    default => sub {
      my ($self) = @_;
      my $tester = $self->authenticated_tester;
      $tester->default_arguments({
        %{ $tester->default_arguments },
        accountId => $self->accountId,
      });
      return $tester;
    },
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

  sub create_mailbox {
    # XXX - This should probably not use Test::* functions and
    #       instead hard fail if something goes wrong.
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ($self, $arg) = @_;
    state $mb_inc = 0;

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

  sub create_calendar {
    # XXX - This should probably not use Test::* functions and
    #       instead hard fail if something goes wrong.
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ($self, $arg) = @_;
    state $cal_inc = 0;

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

  sub create_calendar_event {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ($self, $arg) = @_;
    state $event_inc = 0;

    $arg ||= {};

    my $calendar = delete($arg->{calendar}) // $self->create_calendar;

    $arg->{calendarIds} ||= { $calendar->id => \1 };
    $arg->{title}       ||= "Event $event_inc at $^T.$$";
    $arg->{start}       ||= '2024-01-15T09:00:00';
    $arg->{timeZone}    ||= 'Etc/UTC';
    $arg->{duration}    ||= 'PT1H';
    $arg->{showWithoutTime} //= \0;
    # jscalendarbis S3.1.2: an Event outside a Group MUST set "version", and
    # a JSCalendar 2.0 server rejects one without it.
    $arg->{version}     ||= '2.0';
    $event_inc++;

    my $batch = $self->create_batch(calendarEvent => {
      x => $arg,
    });

    batch_ok($batch);

    ok($batch->is_entirely_successful, "created a calendar event")
      or diag explain $batch->all_results;

    return $batch->result_for('x');
  }

  sub create_address_book {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ($self, $arg) = @_;
    state $ab_inc = 0;

    $arg ||= {};
    $arg->{name} ||= "AddressBook $ab_inc at $^T.$$";
    $ab_inc++;

    my $batch = $self->create_batch(addressBook => {
      x => $arg,
    });

    batch_ok($batch);

    ok($batch->is_entirely_successful, "created an address book")
      or diag explain $batch->all_results;

    return $batch->result_for('x');
  }

  sub create_contact_card {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ($self, $arg) = @_;
    state $card_inc = 0;

    $arg ||= {};
    $arg->{'@type'}  ||= 'Card';
    $arg->{version}  ||= '1.0';
    $arg->{name}     ||= { full => "Test Contact $card_inc" };
    $card_inc++;

    my $batch = $self->create_batch(contactCard => {
      x => $arg,
    });

    batch_ok($batch);

    ok($batch->is_entirely_successful, "created a contact card")
      or diag explain $batch->all_results;

    return $batch->result_for('x');
  }

  no Moose::Role;
}

1;
