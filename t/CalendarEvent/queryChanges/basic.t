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
    title      => 'QC Seed Event',
    calendarIds => { $calendar->id => \1 },
  });

  my %args = (
    filter => { inCalendar => $calendar->id },
    sort   => [{ property => 'start', isAscending => jtrue() }],
  );

  my $res = $tester->request([[
    "CalendarEvent/query" => \%args,
  ]]);
  ok($res->is_success, "CalendarEvent/query baseline") or diag explain $res->response_payload;

  my $base = $res->single_sentence("CalendarEvent/query")->arguments;
  my $query_state = $base->{queryState};
  ok(defined $query_state, "got queryState");
  # RFC 8620 S5.5 lets a server answer canCalculateChanges false for a given
  # filter/sort; nothing to test then.
  ok(defined $base->{canCalculateChanges}, "has canCalculateChanges");
  unless ($base->{canCalculateChanges}) {
    note("server does not support CalendarEvent/queryChanges for this "
       . "filter/sort, so the rest of this file does not apply");
    return;
  }

  subtest "no changes" => sub {
    my $res = $tester->request([[
      "CalendarEvent/queryChanges" => {
        %args,
        sinceQueryState => $query_state,
      },
    ]]);
    ok($res->is_success, "CalendarEvent/queryChanges") or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("CalendarEvent/queryChanges")->arguments,
      superhashof({
        oldQueryState => jstr($query_state),
        newQueryState => jstr($query_state),
        added         => [],
        removed       => [],
      }),
      "no-changes response",
    ) or diag explain $res->as_stripped_triples;
  };

  my $event2 = $account->create_calendar_event({
    title      => 'QC Added Event',
    start      => '2025-06-01T10:00:00',
    calendarIds => { $calendar->id => \1 },
  });

  subtest "created event appears in added" => sub {
    my $res = $tester->request([[
      "CalendarEvent/queryChanges" => {
        %args,
        sinceQueryState => $query_state,
      },
    ]]);
    ok($res->is_success, "CalendarEvent/queryChanges") or diag explain $res->response_payload;

    my $args_out = $res->single_sentence("CalendarEvent/queryChanges")->arguments;
    jcmp_deeply(
      $args_out,
      superhashof({
        oldQueryState => jstr($query_state),
        newQueryState => none(jstr($query_state)),
        added         => supersetof(superhashof({ id => jstr($event2->id) })),
        removed       => ignore,
      }),
      "new event in added",
    ) or diag explain $res->as_stripped_triples;

    $query_state = $args_out->{newQueryState};
  };

  $tester->request_ok(
    [ "CalendarEvent/set" => { destroy => [ $event1->id ] } ],
    superhashof({ destroyed => [ $event1->id ] }),
    "destroyed event",
  );

  subtest "destroyed event appears in removed" => sub {
    my $res = $tester->request([[
      "CalendarEvent/queryChanges" => {
        %args,
        sinceQueryState => $query_state,
      },
    ]]);
    ok($res->is_success, "CalendarEvent/queryChanges") or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("CalendarEvent/queryChanges")->arguments,
      superhashof({
        oldQueryState => jstr($query_state),
        newQueryState => none(jstr($query_state)),
        removed       => supersetof($event1->id),
        added         => ignore,
      }),
      "destroyed event in removed",
    ) or diag explain $res->as_stripped_triples;
  };
};
