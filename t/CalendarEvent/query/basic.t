use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $calendar = $account->create_calendar;

  my $event1 = $account->create_calendar_event({
    title       => 'Query Event 1',
    start       => '2024-03-01T09:00:00',
    timeZone    => 'Etc/UTC',
    duration    => 'PT1H',
    showWithoutTime => \0,
    calendarIds => { $calendar->id => \1 },
  });
  my $event2 = $account->create_calendar_event({
    title       => 'Query Event 2',
    start       => '2024-03-02T10:00:00',
    timeZone    => 'Etc/UTC',
    duration    => 'PT1H',
    showWithoutTime => \0,
    calendarIds => { $calendar->id => \1 },
  });

  subtest "Query events in calendar" => sub {
    my $res = $tester->request([[
      "CalendarEvent/query" => {
        filter => { inCalendar => $calendar->id },
      },
    ]]);
    ok($res->is_success, "CalendarEvent/query")
      or diag explain $res->response_payload;

    my $args = $res->single_sentence("CalendarEvent/query")->arguments;
    ok(defined $args->{queryState}, 'has queryState');

    my %ids = map { $_ => 1 } @{ $args->{ids} // [] };
    ok($ids{ $event1->id }, 'event1 in results');
    ok($ids{ $event2->id }, 'event2 in results');
  };

  subtest "Query with time range" => sub {
    my $res = $tester->request([[
      "CalendarEvent/query" => {
        filter => {
          inCalendar => $calendar->id,
          after      => '2024-03-01T00:00:00',
          before     => '2024-03-02T00:00:00',
        },
      },
    ]]);
    ok($res->is_success, "CalendarEvent/query with time range");

    my $args = $res->single_sentence("CalendarEvent/query")->arguments;
    my %ids = map { $_ => 1 } @{ $args->{ids} // [] };
    ok($ids{ $event1->id },  'event1 in range results');
    ok(!$ids{ $event2->id }, 'event2 not in range');
  };
};
