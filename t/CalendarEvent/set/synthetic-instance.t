use jmaptest;

# draft-ietf-jmap-calendars S5.9: for a synthetic id "the server MUST process
# an update as an update to the recurrence override for that instance on the
# base event, and a destroy as removing just that instance".

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
  });

  my $expand = sub {
    my $res = $tester->request([
      [ "CalendarEvent/query" => {
          filter => {
            inCalendar => $calendar->id,
            after      => '2024-04-01T00:00:00',
            before     => '2024-04-06T00:00:00',
          },
          expandRecurrences => \1,
        }, 'q' ],
      [ "CalendarEvent/get" => {
          '#ids'     => { resultOf => 'q', name => 'CalendarEvent/query', path => '/ids' },
          properties => [qw(id baseEventId recurrenceId title)],
        }, 'g' ],
    ]);
    my $list = $res->sentence_named("CalendarEvent/get")->arguments->{list} // [];
    return { map {; $_->{recurrenceId} => $_ } @$list };
  };

  my $before = $expand->();
  is(scalar keys %$before, 5, 'five instances') or diag explain $before;
  my $second = $before->{'2024-04-02T09:00:00'}{id};
  my $fourth = $before->{'2024-04-04T09:00:00'}{id};
  ok($second && $fourth, 'found the Apr 2 and Apr 4 instances') or return;

  subtest "update of an instance becomes an override" => sub {
    my $res = $tester->request([[
      "CalendarEvent/set" => { update => { $second => { title => 'Changed' } } },
    ]]);
    my $args = $res->single_sentence("CalendarEvent/set")->arguments;
    ok(exists $args->{updated}{$second}, 'instance id is in updated')
      or return diag explain $res->as_stripped_triples;

    my $gres = $tester->request([[
      "CalendarEvent/get" => {
        ids        => [ $base->id ],
        properties => [qw(title recurrenceOverrides)],
      },
    ]]);
    my $ev = $gres->single_sentence("CalendarEvent/get")->arguments->{list}[0];
    is($ev->{title}, 'Daily', 'base title unchanged') or diag explain $ev;
    is($ev->{recurrenceOverrides}{'2024-04-02T09:00:00'}{title}, 'Changed',
       'base event has an override for Apr 2 with the new title')
      or diag explain $ev;

    my $now = $expand->();
    is($now->{'2024-04-02T09:00:00'}{title}, 'Changed', 'Apr 2 instance changed');
    is($now->{'2024-04-03T09:00:00'}{title}, 'Daily',   'Apr 3 instance unchanged');
  };

  subtest "destroy of an instance removes just that instance" => sub {
    my $res = $tester->request([[
      "CalendarEvent/set" => { destroy => [ $fourth ] },
    ]]);
    my $args = $res->single_sentence("CalendarEvent/set")->arguments;
    jcmp_deeply($args->{destroyed}, [ $fourth ], 'instance id is in destroyed')
      or return diag explain $res->as_stripped_triples;

    my $gres = $tester->request([[
      "CalendarEvent/get" => { ids => [ $base->id ], properties => ['id'] },
    ]]);
    is(scalar @{ $gres->single_sentence("CalendarEvent/get")->arguments->{list} }, 1,
       'base event still exists');

    my $now = $expand->();
    jcmp_deeply(
      [ sort keys %$now ],
      [ map {; "2024-04-0${_}T09:00:00" } 1, 2, 3, 5 ],
      'only the Apr 4 instance is gone',
    ) or diag explain $now;
  };
};
