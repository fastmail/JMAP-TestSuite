use jmaptest;

use JMAP::TestSuite::Util qw(fetch_session);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  subtest "Destroy an empty calendar" => sub {
    my $calendar = $account->create_calendar;
    my $id = $calendar->id;

    my $res = $tester->request([[
      "Calendar/set" => {
        destroy => [$id],
      },
    ]]);
    ok($res->is_success, "Calendar/set destroy")
      or diag explain $res->response_payload;

    my $args = $res->single_sentence("Calendar/set")->arguments;

    jcmp_deeply(
      $args,
      superhashof({
        accountId => jstr($account->accountId),
        oldState  => any(undef, jstr()),
        newState  => jstr(),
        destroyed => [$id],
      }),
      "destroy response looks good",
    ) or diag explain $res->as_stripped_triples;

    ok(!$args->{notDestroyed}{$id}, 'not in notDestroyed');

    subtest "Verify gone via get" => sub {
      my $get_res = $tester->request([[
        "Calendar/get" => { ids => [$id] },
      ]]);
      my $get_args = $get_res->single_sentence("Calendar/get")->arguments;
      ok(grep { $_ eq $id } @{$get_args->{notFound}}, 'id in notFound after destroy');
      is(scalar @{$get_args->{list}}, 0, 'list is empty');
    };
  };

  subtest "Destroy calendar with events fails without onDestroyRemoveEvents" => sub {
    my $calendar = $account->create_calendar;
    $account->create_calendar_event({ calendar => $calendar });

    my $res = $tester->request([[
      "Calendar/set" => {
        destroy => [$calendar->id],
      },
    ]]);
    ok($res->is_success, "Calendar/set destroy with events");

    my $args = $res->single_sentence("Calendar/set")->arguments;
    ok($args->{notDestroyed}{ $calendar->id }, 'calendar with events in notDestroyed');
    is($args->{notDestroyed}{ $calendar->id }{type}, 'calendarHasEvent', 'correct error type');
    ok(!(grep { $_ eq $calendar->id } @{$args->{destroyed} // []}), 'not in destroyed');
  };

  subtest "Destroy calendar with events succeeds with onDestroyRemoveEvents" => sub {
    my $calendar = $account->create_calendar;
    my $event    = $account->create_calendar_event({ calendar => $calendar });

    my $res = $tester->request([[
      "Calendar/set" => {
        destroy               => [$calendar->id],
        onDestroyRemoveEvents => \1,
      },
    ]]);
    ok($res->is_success, "Calendar/set destroy with onDestroyRemoveEvents")
      or diag explain $res->response_payload;

    my $args = $res->single_sentence("Calendar/set")->arguments;
    ok(grep { $_ eq $calendar->id } @{$args->{destroyed} // []}, 'calendar destroyed');
    ok(!$args->{notDestroyed}{ $calendar->id }, 'not in notDestroyed');

    subtest "Events also gone" => sub {
      my $get_res = $tester->request([[
        "CalendarEvent/get" => { ids => [$event->id] },
      ]]);
      my $get_args = $get_res->single_sentence("CalendarEvent/get")->arguments;
      ok(grep { $_ eq $event->id } @{$get_args->{notFound}}, 'event in notFound after calendar destroy');
    };
  };

  subtest "Event in a second calendar survives" => sub {
    # draft-ietf-jmap-calendars S1.5.1: maxCalendarsPerEvent is null or >= 1.
    my $session = fetch_session($tester) or return;
    my $max = $session->{accounts}{ $account->accountId }{accountCapabilities}
                {'urn:ietf:params:jmap:calendars'}{maxCalendarsPerEvent};
    if (defined $max && $max < 2) {
      note("maxCalendarsPerEvent is $max; skipping");
      return;
    }

    my $cal1  = $account->create_calendar;
    my $cal2  = $account->create_calendar;
    my $event = $account->create_calendar_event({
      calendar    => $cal1,
      calendarIds => { $cal1->id => \1, $cal2->id => \1 },
    });

    my $res = $tester->request([[
      "Calendar/set" => {
        destroy               => [$cal1->id],
        onDestroyRemoveEvents => \1,
      },
    ]]);
    ok((grep { $_ eq $cal1->id }
          @{ $res->single_sentence("Calendar/set")->arguments->{destroyed} // [] }),
       'first calendar destroyed')
      or diag explain $res->as_stripped_triples;

    # S4.3: events are removed from the calendar, and destroyed only "if in
    # no other Calendars".
    my $get_res = $tester->request([[
      "CalendarEvent/get" => { ids => [$event->id], properties => ['calendarIds'] },
    ]]);
    my $list = $get_res->single_sentence("CalendarEvent/get")->arguments->{list};
    is(scalar @$list, 1, 'event still exists') or return diag explain $get_res->as_stripped_triples;
    jcmp_deeply(
      $list->[0]{calendarIds},
      { $cal2->id => jtrue },
      'event now belongs only to the surviving calendar',
    ) or diag explain $list;
  };

  subtest "Destroy unknown id returns notFound" => sub {
    my $res = $tester->request([[
      "Calendar/set" => {
        destroy => ['notarealid'],
      },
    ]]);
    ok($res->is_success, "Calendar/set destroy unknown id");

    my $args = $res->single_sentence("Calendar/set")->arguments;
    ok($args->{notDestroyed}{notarealid}, 'unknown id in notDestroyed');
    is($args->{notDestroyed}{notarealid}{type}, 'notFound', 'correct error type');
  };

  subtest "State advances after destroy" => sub {
    my $calendar = $account->create_calendar;

    my $state_before = $tester->request([[
      "Calendar/get" => { ids => [] },
    ]])->single_sentence("Calendar/get")->arguments->{state};

    $tester->request([[
      "Calendar/set" => { destroy => [$calendar->id] },
    ]]);

    my $state_after = $tester->request([[
      "Calendar/get" => { ids => [] },
    ]])->single_sentence("Calendar/get")->arguments->{state};

    isnt($state_after, $state_before, 'state changed after destroy');
  };
};
