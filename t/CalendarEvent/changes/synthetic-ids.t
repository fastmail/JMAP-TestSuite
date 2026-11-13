use jmaptest;

# draft-ietf-jmap-calendars S5.8: synthetic ids "do not appear in
# CalendarEvent/changes responses; only the ids of events as actually stored".

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
    start          => '2024-04-01T09:00:00',
    timeZone       => 'Etc/UTC',
    recurrenceRule => { frequency => 'daily', count => 3 },
  });

  my $state = $tester->request([[
    "CalendarEvent/get" => { ids => [] },
  ]])->single_sentence("CalendarEvent/get")->arguments->{state};

  my $qres = $tester->request([[
    "CalendarEvent/query" => {
      filter => {
        inCalendar => $calendar->id,
        after      => '2024-04-01T00:00:00',
        before     => '2024-04-04T00:00:00',
      },
      expandRecurrences => \1,
    },
  ]]);
  my $ids = $qres->single_sentence("CalendarEvent/query")->arguments->{ids} // [];
  is(scalar @$ids, 3, 'three instances') or return diag explain $qres->as_stripped_triples;

  my $sres = $tester->request([[
    "CalendarEvent/set" => {
      update  => { $ids->[0] => { title => 'Changed instance' } },
      destroy => [ $ids->[1] ],
    },
  ]]);
  my $sargs = $sres->single_sentence("CalendarEvent/set")->arguments;
  ok(exists $sargs->{updated}{ $ids->[0] } && @{ $sargs->{destroyed} // [] },
     'instance update and destroy succeeded')
    or return diag explain $sres->as_stripped_triples;

  my $res = $tester->request([[
    "CalendarEvent/changes" => { sinceState => $state },
  ]]);
  my $args = $res->single_sentence("CalendarEvent/changes")->arguments;
  my %synthetic = map {; $_ => 1 } @$ids;
  my @all = map {; @{ $args->{$_} // [] } } qw(created updated destroyed);

  ok(!(grep { $synthetic{$_} } @all), 'no synthetic id in changes')
    or diag explain $args;
  ok((grep { $_ eq $base->id } @{ $args->{updated} // [] }), 'base event is in updated')
    or diag explain $args;
};
