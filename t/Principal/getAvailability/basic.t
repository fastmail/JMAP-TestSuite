use jmaptest;

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
};
