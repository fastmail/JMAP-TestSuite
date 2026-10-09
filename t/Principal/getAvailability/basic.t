use jmaptest;

use JMAP::TestSuite::Util qw(fetch_session);

attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:principals',
    'urn:ietf:params:jmap:principals:availability',
    'urn:ietf:params:jmap:calendars',
    # draft-ietf-jmap-calendars section 1.5.2: this capability "represents
    # support for the Principal/getAvailability method", so a server may
    # refuse the method unless the request lists it in "using".
    'urn:ietf:params:jmap:principals:availability',
  );

  # RFC 8620 S5.1 lets Principal/get answer requestTooLarge to a null "ids",
  # so find the principals owning this account through Principal/query.
  my $qres = $tester->request([[
    "Principal/query" => { filter => { accountIds => [ $account->accountId ] } },
  ]]);
  my $prin_ids = eval { $qres->single_sentence("Principal/query")->arguments->{ids} };
  my $prin_res = $tester->request([[
    "Principal/get" => { ids => $prin_ids // [] },
  ]]);
  # draft-ietf-jmap-calendars S2.1: the calendars capability of a Principal
  # names the account holding its calendar data; failing that, a lone owner
  # of this account (RFC 9670 S2.4 accountIds filter) is the one.
  my $principal_id = eval {
    my @list = @{ $prin_res->single_sentence("Principal/get")->arguments->{list} };
    my ($mine) = grep {
      my $cal = ($_->{capabilities} // {})->{'urn:ietf:params:jmap:calendars'};
      ($cal && $cal->{accountId} // q{}) eq $account->accountId
    } @list;
    ($mine // (@list == 1 ? $list[0] : undef))->{id};
  };
  unless ($principal_id) {
    plan skip_all => "no Principal has its calendar data in this account";
    return;
  }

  # draft-ietf-jmap-calendars S2.2 counts only subscribed calendars whose
  # includeInAvailability is "all" or "attending"; S4 only says SHOULD default.
  my $calendar = $account->create_calendar({
    isSubscribed          => \1,
    includeInAvailability => 'all',
  });

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
      # draft-ietf-jmap-calendars S2.2: busyStatus is optional, default
      # "unavailable", and if present MUST be one of the three values.
      jcmp_deeply(
        $bp,
        superhashof({
          utcStart => jstr(),
          utcEnd   => jstr(),
          (exists $bp->{busyStatus}
            ? (busyStatus => any(map {; jstr($_) } qw(confirmed tentative unavailable)))
            : ()),
        }),
        "busy period has required fields",
      ) or diag explain $bp;
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

    # draft-ietf-jmap-calendars S2.2: notFound when "No Principal with this
    # id exists".
    my $sent = $res->single_sentence;
    is($sent->name, 'error', "got error for unknown principal");
    is($sent->arguments->{type}, 'notFound', "error is notFound")
      or diag explain $sent->arguments;
  };

  subtest "showDetails and eventProperties" => sub {
    my $detailed = $account->create_calendar_event({
      title       => 'Detailed Meeting',
      start       => '2025-07-02T10:00:00',
      timeZone    => 'Etc/UTC',
      duration    => 'PT1H',
      calendar    => $calendar,
    });

    my $ours = sub {
      my (%arg) = @_;
      my $res = $tester->request([[
        "Principal/getAvailability" => {
          id       => $principal_id,
          utcStart => '2025-07-02T00:00:00Z',
          utcEnd   => '2025-07-03T00:00:00Z',
          %arg,
        },
      ]]);
      my $list = eval { $res->single_sentence("Principal/getAvailability")->arguments->{list} };
      my ($bp) = grep { $_->{utcStart} eq '2025-07-02T10:00:00Z' } @{ $list // [] };
      ok($bp, 'found the busy period') or diag explain $res->as_stripped_triples;
      return $bp // {};
    };

    # S2.2: event is null and accountId "null if the event property is null"
    # when "The showDetails argument is false".
    my $bp = $ours->(showDetails => \0);
    jcmp_deeply(
      $bp,
      superhashof({ event => undef, accountId => undef }),
      'showDetails false: event and accountId are null',
    ) or diag explain $bp;

    $bp = $ours->(showDetails => \1);
    jcmp_deeply(
      $bp,
      superhashof({
        accountId => jstr($account->accountId),
        event     => superhashof({ title => jstr('Detailed Meeting') }),
      }),
      'showDetails true: the event and its account are returned',
    ) or diag explain $bp;

    # S2.2: properties "not in the eventProperties list are removed".
    $bp = $ours->(showDetails => \1, eventProperties => [qw(id title)]);
    jcmp_deeply(
      $bp->{event},
      all(
        superhashof({ title => jstr('Detailed Meeting') }),
        code(sub {
          my @extra = grep { $_ ne 'id' && $_ ne 'title' } keys %{ $_[0] };
          @extra ? (0, "unrequested properties: @extra") : 1;
        }),
      ),
      'eventProperties limits the event to the listed properties',
    ) or diag explain $bp;
  };

  subtest "tooLarge" => sub {
    my $session = fetch_session($tester) or return;
    my $max = $session->{accounts}{ $account->accountId }{accountCapabilities}
                {'urn:ietf:params:jmap:principals:availability'}{maxAvailabilityDuration};

    # jscalendarbis S1.5.6: only weeks and days carry the calendar part.
    my ($w, $d) = (defined $max ? $max : '') =~ /\AP(?:(\d+)W)?(?:(\d+)D)?/;
    my $days = ($w // 0) * 7 + ($d // 0) + 1;
    if (!defined $max || $days > 30 * 365) {
      note('no usable maxAvailabilityDuration; skipping');
      return;
    }

    my $res = $tester->request([[
      "Principal/getAvailability" => {
        id       => $principal_id,
        utcStart => '2000-01-01T00:00:00Z',
        utcEnd   => '2031-01-01T00:00:00Z',
      },
    ]]);
    # S2.2 lists tooLarge among the errors that "may be returned".
    my $s = $res->single_sentence;
    if ($s->name ne 'error') {
      note("server calculated a range over its maxAvailabilityDuration $max");
      return;
    }
    is($s->arguments->{type}, 'tooLarge', "a range over $max is tooLarge")
      or diag explain $s->arguments;
  };

  subtest "free, cancelled and secret events are not busy" => sub {
    # S2.2: relevant events are busy, not "cancelled", and not "secret".
    my %ignored = (
      '2025-07-03T09:00:00' => { freeBusyStatus => 'free' },
      '2025-07-03T11:00:00' => { status => 'cancelled' },
      '2025-07-03T13:00:00' => { privacy => 'secret' },
    );
    for my $start (sort keys %ignored) {
      $account->create_calendar_event({
        %{ $ignored{$start} },
        start       => $start,
        timeZone    => 'Etc/UTC',
        duration    => 'PT1H',
        calendar    => $calendar,
      });
    }
    $account->create_calendar_event({
      start       => '2025-07-03T15:00:00',
      timeZone    => 'Etc/UTC',
      duration    => 'PT1H',
      calendar    => $calendar,
    });

    my $res = $tester->request([[
      "Principal/getAvailability" => {
        id       => $principal_id,
        utcStart => '2025-07-03T00:00:00Z',
        utcEnd   => '2025-07-04T00:00:00Z',
      },
    ]]);
    my $list = eval { $res->single_sentence("Principal/getAvailability")->arguments->{list} };
    ok($list, 'got a list') or return diag explain $res->as_stripped_triples;

    ok((grep { $_->{utcStart} eq '2025-07-03T15:00:00Z' } @$list), 'the busy event is listed')
      or diag explain $list;
    for my $start (sort keys %ignored) {
      my ($key) = keys %{ $ignored{$start} };
      my ($from, $to) = ("${start}Z", substr($start, 0, 11) . sprintf('%02d:00:00Z', substr($start, 11, 2) + 1));
      ok(!(grep { $_->{utcStart} lt $to && $_->{utcEnd} gt $from } @$list),
         "$key $ignored{$start}{$key}: no busy period")
        or diag explain $list;
    }
  };

  subtest "event-less periods are merged" => sub {
    # 10:00-11:00 abuts 11:00-12:00; 14:00-15:30 overlaps 15:00-16:00.
    for my $slot (['10:00', 'PT1H'], ['11:00', 'PT1H'], ['14:00', 'PT1H30M'], ['15:00', 'PT1H']) {
      $account->create_calendar_event({
        start       => "2025-07-04T$slot->[0]:00",
        timeZone    => 'Etc/UTC',
        duration    => $slot->[1],
        calendar    => $calendar,
      });
    }

    my $res = $tester->request([[
      "Principal/getAvailability" => {
        id          => $principal_id,
        utcStart    => '2025-07-04T00:00:00Z',
        utcEnd      => '2025-07-05T00:00:00Z',
        showDetails => \0,
      },
    ]]);
    my $list = eval { $res->single_sentence("Principal/getAvailability")->arguments->{list} };
    ok($list, 'got a list') or return diag explain $res->as_stripped_triples;

    # S2.2: event-less periods MUST NOT overlap, and touching ones MUST differ
    # in busyStatus (default "unavailable").
    my @null = sort { $a->{utcStart} cmp $b->{utcStart} } grep { !defined $_->{event} } @$list;
    for my $i (1 .. $#null) {
      my ($p, $q) = @null[ $i - 1, $i ];
      ok(
        $p->{utcEnd} lt $q->{utcStart}
          || ($p->{utcEnd} eq $q->{utcStart}
              && ($p->{busyStatus} // 'unavailable') ne ($q->{busyStatus} // 'unavailable')),
        "$p->{utcStart}..$p->{utcEnd} and $q->{utcStart}..$q->{utcEnd} are separate",
      ) or diag explain \@null;
    }

    my %span = map {; "$_->{utcStart}/$_->{utcEnd}" => 1 } @null;
    ok($span{'2025-07-04T10:00:00Z/2025-07-04T12:00:00Z'}, 'adjacent events merged into one period')
      or diag explain \@null;
    ok($span{'2025-07-04T14:00:00Z/2025-07-04T16:00:00Z'}, 'overlapping events merged into one period')
      or diag explain \@null;
  };
};
