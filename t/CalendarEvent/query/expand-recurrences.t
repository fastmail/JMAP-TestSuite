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

  # Three occurrences fall inside the range queried below.
  my $res = $tester->request([[
    "CalendarEvent/set" => {
      create => {
        rec => {
          calendarIds    => { $calendar->id => \1 },
          title          => 'Weekly Standup',
          start          => '2024-04-01T09:00:00',
          timeZone       => 'Etc/UTC',
          duration       => 'PT30M',
          showWithoutTime => \0,
          version         => '2.0',
          recurrenceRule => {
            frequency => 'weekly',
            count     => 5,
          },
        },
      },
    },
  ]]);
  ok($res->is_success, "CalendarEvent/set create recurring")
    or diag explain $res->response_payload;

  my $master_id = $res->single_sentence("CalendarEvent/set")->arguments->{created}{rec}{id};
  ok($master_id, 'got master event id');

  subtest "Query without expandRecurrences returns master" => sub {
    my $qres = $tester->request([[
      "CalendarEvent/query" => {
        filter => { inCalendar => $calendar->id },
      },
    ]]);
    ok($qres->is_success, "CalendarEvent/query");

    my $ids = $qres->single_sentence("CalendarEvent/query")->arguments->{ids} // [];
    ok(grep { $_ eq $master_id } @$ids, 'master id in results');
  };

  subtest "Query with expandRecurrences returns occurrences" => sub {
    my $qres = $tester->request([[
      "CalendarEvent/query" => {
        filter => {
          inCalendar => $calendar->id,
          after      => '2024-04-01T00:00:00',
          before     => '2024-04-22T00:00:00',
        },
        expandRecurrences => \1,
      },
    ]]);
    ok($qres->is_success, "CalendarEvent/query with expandRecurrences")
      or diag explain $qres->response_payload;

    my $args = $qres->single_sentence("CalendarEvent/query")->arguments;
    my $ids  = $args->{ids} // [];

    # 3 weekly occurrences: Apr 1, Apr 8, Apr 15
    cmp_ok(scalar @$ids, '>=', 3, 'got at least 3 occurrences');

    # Instance ids are opaque; baseEventId is what marks a synthetic instance.
    my $gres = $tester->request([[
      "CalendarEvent/get" => {
        ids        => $ids,
        properties => [ 'id', 'baseEventId' ],
      },
    ]]);
    ok($gres->is_success, "CalendarEvent/get on the expanded ids")
      or diag explain $gres->response_payload;

    my $list = $gres->single_sentence("CalendarEvent/get")->arguments->{list} // [];
    is(scalar @$list, scalar @$ids, 'every queried id was fetchable');

    my @ours = grep {
      $_->{id} eq $master_id
        || (defined $_->{baseEventId} && $_->{baseEventId} eq $master_id)
    } @$list;
    cmp_ok(scalar @ours, '>=', 3,
      'at least 3 returned events belong to the master event');

    # canCalculateChanges must be false when expanding
    ok(!$args->{canCalculateChanges}, 'canCalculateChanges is false');
  };
};
