use jmaptest;

attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:principals',
  );

  my $prin_res = $tester->request([[
    "Principal/get" => {},
  ]]);
  my $principal_id = eval {
    $prin_res->single_sentence("Principal/get")->arguments->{list}[0]{id};
  };
  unless ($principal_id) {
    plan skip_all => "Principal/get without ids did not return a principal (server may be non-compliant)";
    return;
  }

  my $calendar = $account->create_calendar;

  my $event = $account->create_calendar_event({
    title      => 'Busy Meeting',
    start      => '2025-07-01T10:00:00',
    timeZone   => 'Etc/UTC',
    duration   => 'PT1H',
    calendarIds => { $calendar->id => \1 },
  });

  subtest "window containing the event" => sub {
    my $res = $tester->request([[
      "Principal/getAvailability" => {
        id       => $principal_id,
        utcStart => '2025-07-01T00:00:00Z',
        utcEnd   => '2025-07-02T00:00:00Z',
      },
    ]]);
    ok($res->is_success, "Principal/getAvailability") or diag explain $res->response_payload;

    my $args = $res->single_sentence("Principal/getAvailability")->arguments;
    ok(defined $args->{list}, "has list");

    my @busy = @{ $args->{list} };
    ok(@busy >= 1, "at least one busy period in window");

    my $found = grep {
      $_->{utcStart} eq '2025-07-01T10:00:00Z' &&
      $_->{utcEnd}   eq '2025-07-01T11:00:00Z'
    } @busy;
    ok($found, "found our busy event") or diag explain \@busy;

    for my $bp (@busy) {
      jcmp_deeply(
        $bp,
        superhashof({
          utcStart   => jstr(),
          utcEnd     => jstr(),
          busyStatus => jstr(),
        }),
        "busy period has required fields",
      );
    }
  };

  subtest "window before the event" => sub {
    my $res = $tester->request([[
      "Principal/getAvailability" => {
        id       => $principal_id,
        utcStart => '2025-06-01T00:00:00Z',
        utcEnd   => '2025-06-02T00:00:00Z',
      },
    ]]);
    ok($res->is_success, "Principal/getAvailability");

    my $args = $res->single_sentence("Principal/getAvailability")->arguments;
    my @busy = @{ $args->{list} };

    my $found = grep { $_->{utcStart} eq '2025-07-01T10:00:00Z' } @busy;
    ok(!$found, "event not in window before it");
  };

  subtest "unknown principal returns error" => sub {
    my $res = $tester->request([[
      "Principal/getAvailability" => {
        id       => 'nonexistent',
        utcStart => '2025-07-01T00:00:00Z',
        utcEnd   => '2025-07-02T00:00:00Z',
      },
    ]]);
    ok($res->is_success, "request succeeded");

    my $sent = $res->single_sentence;
    is($sent->name, 'error', "got error for unknown principal");
  };
};
