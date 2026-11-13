use jmaptest;

# draft-ietf-jmap-calendars S5: utcStart and utcEnd are "not included by
# default and must be requested explicitly"; S5.7: the timeZone argument
# (default "Etc/UTC") is used for them on floating events.

sub utc { my $t = shift; re(qr/\A\Q$t\E(?:\.0+)?Z\z/) }

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $calendar = $account->create_calendar;

  my $res = $tester->request([[
    "CalendarEvent/set" => {
      create => {
        floating => {
          calendarIds     => { $calendar->id => \1 },
          title           => "Floating $^T.$$",
          start           => '2024-05-01T09:00:00',
          duration        => 'PT1H',
          showWithoutTime => \0,
          version         => '2.0',
        },
        berlin => {
          calendarIds     => { $calendar->id => \1 },
          title           => "Berlin $^T.$$",
          start           => '2024-05-01T09:00:00',
          timeZone        => 'Europe/Berlin',
          duration        => 'PT1H',
          showWithoutTime => \0,
          version         => '2.0',
        },
      },
    },
  ]]);
  my $created  = $res->single_sentence("CalendarEvent/set")->arguments->{created};
  my $floating = $created->{floating}{id};
  my $berlin   = $created->{berlin}{id};
  ok($floating && $berlin, 'events created') or return diag explain $res->as_stripped_triples;

  my $get = sub {
    my (%arg) = @_;
    my $r = $tester->request([[ "CalendarEvent/get" => { ids => [ $floating, $berlin ], %arg } ]]);
    return { map {; $_->{id} => $_ } @{ $r->single_sentence("CalendarEvent/get")->arguments->{list} } };
  };

  subtest "not returned by default" => sub {
    my $by_id = $get->();
    for my $id ($floating, $berlin) {
      ok(!exists $by_id->{$id}{utcStart} && !exists $by_id->{$id}{utcEnd},
         "no utcStart or utcEnd on $id") or diag explain $by_id->{$id};
    }
  };

  subtest "default timeZone is Etc/UTC" => sub {
    my $by_id = $get->(properties => [qw(utcStart utcEnd)]);
    jcmp_deeply(
      $by_id,
      {
        $floating => superhashof({ utcStart => utc('2024-05-01T09:00:00'), utcEnd => utc('2024-05-01T10:00:00') }),
        $berlin   => superhashof({ utcStart => utc('2024-05-01T07:00:00'), utcEnd => utc('2024-05-01T08:00:00') }),
      },
      'floating event read as UTC, zoned event in its own zone',
    ) or diag explain $by_id;
  };

  subtest "timeZone argument applies to floating events only" => sub {
    my $by_id = $get->(properties => [qw(utcStart utcEnd)], timeZone => 'America/New_York');
    jcmp_deeply(
      $by_id,
      {
        $floating => superhashof({ utcStart => utc('2024-05-01T13:00:00'), utcEnd => utc('2024-05-01T14:00:00') }),
        $berlin   => superhashof({ utcStart => utc('2024-05-01T07:00:00'), utcEnd => utc('2024-05-01T08:00:00') }),
      },
      'floating event read in America/New_York',
    ) or diag explain $by_id;
  };
};
