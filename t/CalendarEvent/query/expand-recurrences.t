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

    # draft-ietf-jmap-calendars S5.11.1: an instance matches if it ends after
    # "after" and starts before "before", so Apr 1, 8 and 15 but not Apr 22.
    is(scalar @$ids, 3, 'got exactly 3 occurrences') or diag explain $ids;

    # S5.11: "a separate id will be returned for each instance".
    my %distinct = map {; $_ => 1 } @$ids;
    is(scalar keys %distinct, 3, 'occurrence ids are distinct');
    ok(!$distinct{$master_id}, 'master id is not an occurrence id');

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
      defined $_->{baseEventId} && $_->{baseEventId} eq $master_id
    } @$list;
    is(scalar @ours, 3, 'all 3 returned events are instances of the master')
      or diag explain $list;

    # draft-ietf-jmap-calendars places no requirement on canCalculateChanges
    # for an expanded query; it just has to be there.
    ok(defined $args->{canCalculateChanges}, 'canCalculateChanges is present');
  };
};
