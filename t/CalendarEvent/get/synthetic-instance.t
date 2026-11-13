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
  my $base = $account->create_calendar_event({
    calendar       => $calendar,
    title          => 'Daily',
    start          => '2024-04-01T09:00:00',
    timeZone       => 'Etc/UTC',
    duration       => 'PT30M',
    recurrenceRule => { frequency => 'daily', count => 5 },
    recurrenceOverrides => {
      '2024-04-03T09:00:00' => { start => '2024-04-03T10:00:00', title => 'Moved' },
    },
  });

  my @props = qw(id baseEventId title start recurrenceId recurrenceRule recurrenceOverrides);

  subtest "a stored event has no baseEventId" => sub {
    my $res = $tester->request([[
      "CalendarEvent/get" => { ids => [ $base->id ], properties => \@props },
    ]]);
    my $ev = $res->single_sentence("CalendarEvent/get")->arguments->{list}[0];
    ok($ev, 'got the base event') or return diag explain $res->as_stripped_triples;

    # draft-ietf-jmap-calendars S5: baseEventId "is only defined if the id
    # property is a synthetic id".
    ok(!defined $ev->{baseEventId}, 'baseEventId is null or absent')
      or diag explain $ev;
  };

  subtest "an expanded instance resolves its override" => sub {
    my $qres = $tester->request([[
      "CalendarEvent/query" => {
        filter => {
          inCalendar => $calendar->id,
          after      => '2024-04-03T00:00:00',
          before     => '2024-04-04T00:00:00',
        },
        expandRecurrences => \1,
      },
    ]]);
    my $ids = $qres->single_sentence("CalendarEvent/query")->arguments->{ids} // [];
    is(scalar @$ids, 1, 'one instance on Apr 3') or return diag explain $qres->as_stripped_triples;

    my $res = $tester->request([[
      "CalendarEvent/get" => { ids => $ids, properties => \@props },
    ]]);
    my $ev = $res->single_sentence("CalendarEvent/get")->arguments->{list}[0];

    # S5.7: the server "will resolve any overrides and set the appropriate
    # start and recurrenceId"; recurrenceRule/Overrides "MUST be returned as null".
    jcmp_deeply(
      $ev,
      superhashof({
        id                  => jstr($ids->[0]),
        baseEventId         => jstr($base->id),
        title               => jstr('Moved'),
        start               => jstr('2024-04-03T10:00:00'),
        recurrenceId        => jstr('2024-04-03T09:00:00'),
        recurrenceRule      => undef,
        recurrenceOverrides => undef,
      }),
      'instance has resolved start, recurrenceId and null recurrence properties',
    ) or diag explain $res->as_stripped_triples;
  };
};
