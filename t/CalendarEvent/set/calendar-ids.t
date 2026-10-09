use jmaptest;

# draft-ietf-jmap-calendars S5: "An event MUST belong to one or more
# Calendars at all times" and each value in calendarIds "MUST be true".

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $calendar = $account->create_calendar;

  my %event = (
    title           => "calendarIds $^T.$$",
    start           => '2024-05-01T09:00:00',
    timeZone        => 'Etc/UTC',
    duration        => 'PT1H',
    showWithoutTime => \0,
    version         => '2.0',
  );

  my %bad = (
    empty   => {},
    unknown => { 'no-such-calendar' => \1 },
    false   => { $calendar->id => \0 },
  );

  my $res = $tester->request([[
    "CalendarEvent/set" => {
      create => {
        map {; $_ => { %event, calendarIds => $bad{$_} } } keys %bad
      },
    },
  ]]);
  my $args = $res->single_sentence("CalendarEvent/set")->arguments;

  for my $case (sort keys %bad) {
    jcmp_deeply(
      $args->{notCreated}{$case},
      invalid_properties('calendarIds'),
      "create with $case calendarIds is invalidProperties",
    ) or diag explain $res->as_stripped_triples;
  }

  my $ev = $account->create_calendar_event({ calendar => $calendar });

  my %bad_update = (
    'calendarIds {}'            => { calendarIds => {} },
    'removing the last calendar' => { 'calendarIds/' . $calendar->id => undef },
  );

  for my $case (sort keys %bad_update) {
    my $ures = $tester->request([[
      "CalendarEvent/set" => { update => { $ev->id => $bad_update{$case} } },
    ]]);
    jcmp_deeply(
      $ures->single_sentence("CalendarEvent/set")->arguments->{notUpdated}{ $ev->id },
      invalid_properties('calendarIds'),
      "update $case is invalidProperties",
    ) or diag explain $ures->as_stripped_triples;
  }
};
