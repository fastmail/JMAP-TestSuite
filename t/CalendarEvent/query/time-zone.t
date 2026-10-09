use jmaptest;

# draft-ietf-jmap-calendars S5.11: the timeZone argument is "The time zone for
# before/after filter conditions (default: Etc/UTC)".

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $calendar = $account->create_calendar;
  my $event = $account->create_calendar_event({
    calendar => $calendar,
    start    => '2024-03-01T09:00:00',
    timeZone => 'Etc/UTC',
    duration => 'PT1H',
  });

  my $query = sub {
    my ($after, $before, @tz) = @_;
    my $res = $tester->request([[
      "CalendarEvent/query" => {
        filter => { inCalendar => $calendar->id, after => $after, before => $before },
        @tz,
      },
    ]]);
    return eval { $res->single_sentence("CalendarEvent/query")->arguments->{ids} };
  };

  # Auckland is UTC+13 on 1 March 2024, so 09:00-11:00 there is 20:00-22:00
  # UTC the day before, and 21:00-23:00 there is 08:00-10:00 UTC.
  jcmp_deeply($query->('2024-03-01T09:00:00', '2024-03-01T11:00:00'),
              [ $event->id ], 'Etc/UTC by default');
  jcmp_deeply($query->('2024-03-01T09:00:00', '2024-03-01T11:00:00', timeZone => 'Pacific/Auckland'),
              [], 'the same local times in Auckland miss the event');
  jcmp_deeply($query->('2024-03-01T21:00:00', '2024-03-01T23:00:00', timeZone => 'Pacific/Auckland'),
              [ $event->id ], 'Auckland local times covering the event match');
};
