use jmaptest;

# draft-ietf-jmap-calendars S5.11.2: "start", "uid" and "recurrenceId" "MUST
# be supported for sorting".

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $calendar = $account->create_calendar;
  my $tag = "$^T-$$";

  my %ev = map {;
    $_->[0] => $account->create_calendar_event({
      calendar => $calendar,
      start    => $_->[1],
      uid      => "$_->[2]-$tag",
    })->id
  } (
    [ a => '2024-03-03T09:00:00', 'sort-a' ],
    [ b => '2024-03-01T09:00:00', 'sort-c' ],
    [ c => '2024-03-02T09:00:00', 'sort-b' ],
  );

  my %case = (
    'start ascending'  => [ { property => 'start' },                     @ev{qw(b c a)} ],
    'start descending' => [ { property => 'start', isAscending => \0 },  @ev{qw(a c b)} ],
    'uid ascending'    => [ { property => 'uid' },                       @ev{qw(a c b)} ],
    'uid descending'   => [ { property => 'uid', isAscending => \0 },    @ev{qw(b c a)} ],
  );

  for my $name (sort keys %case) {
    my ($sort, @want) = @{ $case{$name} };
    my $res = $tester->request([[
      "CalendarEvent/query" => { filter => { inCalendar => $calendar->id }, sort => [ $sort ] },
    ]]);
    my $ids = eval { $res->single_sentence("CalendarEvent/query")->arguments->{ids} };
    jcmp_deeply($ids, \@want, "sorted by $name") or diag explain $res->as_stripped_triples;
  }

  subtest "recurrenceId" => sub {
    my $cal2 = $account->create_calendar;
    $account->create_calendar_event({
      calendar       => $cal2,
      start          => '2024-04-01T09:00:00',
      recurrenceRule => { frequency => 'daily', count => 3 },
    });

    my $res = $tester->request([
      [ "CalendarEvent/query" => {
          filter => {
            inCalendar => $cal2->id,
            after      => '2024-04-01T00:00:00',
            before     => '2024-04-04T00:00:00',
          },
          expandRecurrences => \1,
          sort              => [ { property => 'recurrenceId', isAscending => \0 } ],
        }, 'q' ],
      [ "CalendarEvent/get" => {
          '#ids'     => { resultOf => 'q', name => 'CalendarEvent/query', path => '/ids' },
          properties => [ 'recurrenceId' ],
        }, 'g' ],
    ]);
    my $ids  = eval { $res->sentence_named("CalendarEvent/query")->arguments->{ids} };
    my $list = eval { $res->sentence_named("CalendarEvent/get")->arguments->{list} } // [];
    my %rid  = map {; $_->{id} => $_->{recurrenceId} } @$list;
    jcmp_deeply(
      [ map {; $rid{$_} } @{ $ids // [] } ],
      [ map {; "2024-04-0${_}T09:00:00" } 3, 2, 1 ],
      'instances sorted by recurrenceId descending',
    ) or diag explain $res->as_stripped_triples;
  };
};
