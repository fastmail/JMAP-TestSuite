use jmaptest;

# draft-ietf-jmap-calendars S5.11.1: text, title and uid FilterConditions.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $calendar = $account->create_calendar;
  my $uid = "filter-uid-$^T-$$";

  my $picnic = $account->create_calendar_event({
    calendar    => $calendar,
    title       => 'Zebra Picnic',
    description => 'Bring the xylophone',
  });
  my $board = $account->create_calendar_event({
    calendar => $calendar,
    title    => 'Board Meeting',
    uid      => $uid,
  });

  # S5.11.1 leaves String matching to the server's index, which may fill
  # asynchronously (Cyrus's rolling squatter), so wait until both events
  # can be found.
  my $indexed = 0;
  for my $attempt (1 .. 30) {
    my $res = $tester->request([
      [ "CalendarEvent/query" => { filter => { inCalendar => $calendar->id, text => 'Zebra' } }, 'a' ],
      [ "CalendarEvent/query" => { filter => { inCalendar => $calendar->id, text => 'Board' } }, 'b' ],
    ]);
    my @found = map {; $_->arguments->{ids} // [] } $res->sentences;
    if ((grep { $_ eq $picnic->id } @{ $found[0] })
     && (grep { $_ eq $board->id } @{ $found[1] })) { $indexed = 1; last }
    sleep 1;
  }
  ok($indexed, 'the events are searchable') or do {
    note('search index never caught up; skipping text and title matches');
    return;
  };

  my %case = (
    'title matches the title' => [ { title => 'Zebra' },       [ $picnic->id ] ],
    'title ignores description' => [ { title => 'xylophone' }, [] ],
    'text matches the description' => [ { text => 'xylophone' }, [ $picnic->id ] ],
    'text matches the title' => [ { text => 'Board' },         [ $board->id ] ],
    'uid matches exactly' => [ { uid => $uid },                [ $board->id ] ],
    'uid is not a substring match' => [ { uid => substr($uid, 0, -1) }, [] ],
  );

  for my $name (sort keys %case) {
    my ($cond, $want) = @{ $case{$name} };
    my $res = $tester->request([[
      "CalendarEvent/query" => { filter => { inCalendar => $calendar->id, %$cond } },
    ]]);
    my $ids = eval { $res->single_sentence("CalendarEvent/query")->arguments->{ids} };
    jcmp_deeply($ids, bag(@$want), $name) or diag explain $res->as_stripped_triples;
  }
};
