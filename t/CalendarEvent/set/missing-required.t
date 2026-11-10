use jmaptest;

use Data::GUID qw(guid_string);

# draft-ietf-jmap-calendars S5.1: "An event MUST belong to one or more
# Calendars at all times", and calendarIds has no default the server is told
# to supply (the default calendar is for clients to choose).  A create
# without it is rejected with invalidProperties naming calendarIds; a server
# that puts the event somewhere instead must at least leave it in a calendar.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  $account->create_calendar;   # so there is somewhere it could go

  my $args = $tester->request([[
    "CalendarEvent/set" => {
      create => {
        e => {
          title    => "No calendar " . guid_string(),
          start    => '2024-06-01T10:00:00',
          timeZone => 'Etc/UTC',
          duration => 'PT1H',
        },
      },
    },
  ]])->single_sentence("CalendarEvent/set")->arguments;

  if (my $err = $args->{notCreated}{e}) {
    jcmp_deeply($err, superhashof({ type => 'invalidProperties', properties => supersetof('calendarIds') }),
      "rejected: invalidProperties naming calendarIds") or diag explain $err;
    return;
  }

  my $id = $args->{created}{e}{id};
  ok($id, "created instead") or return diag explain $args;
  my $event = $tester->request([[
    "CalendarEvent/get" => { ids => [ $id ], properties => [ 'calendarIds' ] },
  ]])->single_sentence("CalendarEvent/get")->arguments->{list}[0];
  ok($event && keys %{ $event->{calendarIds} || {} },
     "then the event is in at least one calendar") or diag explain $event;
};
