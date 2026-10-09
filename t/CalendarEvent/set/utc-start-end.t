use jmaptest;

use JMAP::TestSuite::Comparator::CalendarEvent qw(jduration);

# draft-ietf-jmap-calendars S5.9: utcStart "MUST NOT be set in addition to a
# start property and it cannot be set inside recurrenceOverrides; this MUST
# be rejected with an invalidProperties SetError", and likewise utcEnd.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $calendar = $account->create_calendar;

  my %base = (
    calendarIds     => { $calendar->id => \1 },
    title           => "utc $^T.$$",
    showWithoutTime => \0,
    version         => '2.0',
  );

  my %bad = (
    'utcStart with start' => [ utcStart => {
      start => '2024-05-01T09:00:00', timeZone => 'Etc/UTC', duration => 'PT1H',
      utcStart => '2024-05-01T09:00:00Z',
    } ],
    'utcEnd with duration' => [ utcEnd => {
      start => '2024-05-01T09:00:00', timeZone => 'Etc/UTC', duration => 'PT1H',
      utcEnd => '2024-05-01T10:00:00Z',
    } ],
    'utcStart in an override' => [ recurrenceOverrides => {
      start => '2024-05-01T09:00:00', timeZone => 'Etc/UTC', duration => 'PT1H',
      recurrenceRule      => { frequency => 'daily', count => 3 },
      recurrenceOverrides => {
        '2024-05-02T09:00:00' => { utcStart => '2024-05-02T11:00:00Z' },
      },
    } ],
    'utcEnd in an override' => [ recurrenceOverrides => {
      start => '2024-05-01T09:00:00', timeZone => 'Etc/UTC', duration => 'PT1H',
      recurrenceRule      => { frequency => 'daily', count => 3 },
      recurrenceOverrides => {
        '2024-05-02T09:00:00' => { utcEnd => '2024-05-02T11:00:00Z' },
      },
    } ],
  );

  my %cid = map {; $_ => s/\W+/_/gr } keys %bad;
  my $res = $tester->request([[
    "CalendarEvent/set" => {
      create => {
        map {; $cid{$_} => { %base, %{ $bad{$_}[1] } } } keys %bad
      },
    },
  ]]);
  my $args = $res->single_sentence("CalendarEvent/set")->arguments;

  for my $case (sort keys %bad) {
    jcmp_deeply(
      $args->{notCreated}{ $cid{$case} },
      invalid_properties($bad{$case}[0]),
      "$case is invalidProperties",
    ) or diag explain $res->as_stripped_triples;
  }

  subtest "utcStart and utcEnd alone are translated" => sub {
    my $res = $tester->request([[
      "CalendarEvent/set" => {
        create => {
          ok => { %base, utcStart => '2024-05-01T09:00:00Z', utcEnd => '2024-05-01T10:30:00Z' },
        },
      },
    ]]);
    my $created = $res->single_sentence("CalendarEvent/set")->arguments->{created}{ok};
    ok($created && $created->{id}, 'created') or return diag explain $res->as_stripped_triples;

    # S5: with no timeZone the server "MUST also set this property (and return
    # it in the created/updated response"; the calendar has none, so Etc/UTC.
    is($created->{timeZone}, 'Etc/UTC', 'server-set timeZone is reported in created')
      or diag explain $created;

    my $gres = $tester->request([[
      "CalendarEvent/get" => {
        ids        => [ $created->{id} ],
        properties => [qw(start timeZone duration)],
      },
    ]]);
    jcmp_deeply(
      $gres->single_sentence("CalendarEvent/get")->arguments->{list}[0],
      superhashof({
        start    => jstr('2024-05-01T09:00:00'),
        timeZone => jstr('Etc/UTC'),
        duration => jduration('PT1H30M'),
      }),
      'stored as start, timeZone and duration',
    ) or diag explain $gres->as_stripped_triples;
  };
};
