use jmaptest;

# draft-ietf-jmap-calendars S5.7: with recurrenceOverridesBefore "only
# recurrence overrides with a recurrence id before this date" are returned,
# and with recurrenceOverridesAfter only those "on or after this date".

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my @rids = map {; "2024-04-0${_}T09:00:00" } 2, 3, 4;
  my $event = $account->create_calendar_event({
    start               => '2024-04-01T09:00:00',
    timeZone            => 'Etc/UTC',
    recurrenceRule      => { frequency => 'daily', count => 5 },
    recurrenceOverrides => { map {; $_ => { title => "Override $_" } } @rids },
  });

  my %case = (
    'after, inclusive' => [ { recurrenceOverridesAfter  => '2024-04-03T09:00:00Z' }, @rids[1, 2] ],
    'before, exclusive' => [ { recurrenceOverridesBefore => '2024-04-03T09:00:00Z' }, $rids[0] ],
    'both' => [
      { recurrenceOverridesAfter  => '2024-04-03T00:00:00Z',
        recurrenceOverridesBefore => '2024-04-04T00:00:00Z' },
      $rids[1],
    ],
    'neither' => [ {}, @rids ],
  );

  for my $name (sort keys %case) {
    my ($extra, @want) = @{ $case{$name} };
    my $res = $tester->request([[
      "CalendarEvent/get" => {
        ids        => [ $event->id ],
        properties => [ 'recurrenceOverrides' ],
        %$extra,
      },
    ]]);
    my $ev = $res->single_sentence("CalendarEvent/get")->arguments->{list}[0];
    jcmp_deeply(
      [ sort keys %{ $ev->{recurrenceOverrides} // {} } ],
      \@want,
      "$name: the right overrides are returned",
    ) or diag explain $res->as_stripped_triples;
  }
};
