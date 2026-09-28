use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $calendar = $account->create_calendar;

  my $create_res = $tester->request([[
    "CalendarEvent/set" => {
      create => {
        ev => {
          calendarIds => { $calendar->id => \1 },
          title       => 'Weekly Meeting',
          start       => '2024-05-06T10:00:00',
          timeZone    => 'Etc/UTC',
          duration    => 'PT1H',
          showWithoutTime => \0,
          version         => '2.0',
          recurrenceRule  => {
            frequency => 'weekly',
            count     => 4,
          },
          # Seeded so the pointer patches below are legal: RFC 8620 S5.3
          # requires a patch pointer's parent to already exist.
          recurrenceOverrides => {
            '2024-05-27T10:00:00' => { title => 'Weekly Meeting (last)' },
          },
          locations => {
            room0 => { name => 'Original Room' },
          },
        },
      },
    },
  ]]);
  ok($create_res->is_success, "CalendarEvent/set create")
    or diag explain $create_res->response_payload;

  my $id = $create_res->single_sentence("CalendarEvent/set")->arguments->{created}{ev}{id};
  ok($id, 'got event id');

  subtest "Update title (flat string)" => sub {
    my $res = $tester->request([[
      "CalendarEvent/set" => {
        update => { $id => { title => 'Board Meeting' } },
      },
    ]]);
    ok($res->is_success, "update title");
    my $args = $res->single_sentence("CalendarEvent/set")->arguments;
    ok(exists $args->{updated}{$id}, 'event updated') or diag explain $args->{notUpdated};

    my $got = $tester->request([[
      "CalendarEvent/get" => { ids => [$id], properties => ['title'] },
    ]])->single_sentence("CalendarEvent/get")->arguments->{list}[0];
    is($got->{title}, 'Board Meeting', 'title round-trips');
  };

  subtest "Update start (flat datetime — wire-date round-trip)" => sub {
    my $res = $tester->request([[
      "CalendarEvent/set" => {
        update => { $id => { start => '2024-05-06T14:30:00' } },
      },
    ]]);
    ok($res->is_success, "update start");
    my $args = $res->single_sentence("CalendarEvent/set")->arguments;
    ok(exists $args->{updated}{$id}, 'event updated') or diag explain $args->{notUpdated};

    my $got = $tester->request([[
      "CalendarEvent/get" => { ids => [$id], properties => ['start'] },
    ]])->single_sentence("CalendarEvent/get")->arguments->{list}[0];
    is($got->{start}, '2024-05-06T14:30:00', 'start round-trips');
  };

  subtest "Update timeZone (flat string)" => sub {
    my $res = $tester->request([[
      "CalendarEvent/set" => {
        update => { $id => { timeZone => 'America/New_York' } },
      },
    ]]);
    ok($res->is_success, "update timeZone");
    my $args = $res->single_sentence("CalendarEvent/set")->arguments;
    ok(exists $args->{updated}{$id}, 'event updated') or diag explain $args->{notUpdated};

    my $got = $tester->request([[
      "CalendarEvent/get" => { ids => [$id], properties => ['timeZone'] },
    ]])->single_sentence("CalendarEvent/get")->arguments->{list}[0];
    is($got->{timeZone}, 'America/New_York', 'timeZone round-trips');
  };

  subtest "Update duration (flat duration string)" => sub {
    my $res = $tester->request([[
      "CalendarEvent/set" => {
        update => { $id => { duration => 'PT90M' } },
      },
    ]]);
    ok($res->is_success, "update duration");
    my $args = $res->single_sentence("CalendarEvent/set")->arguments;
    ok(exists $args->{updated}{$id}, 'event updated') or diag explain $args->{notUpdated};

    my $got = $tester->request([[
      "CalendarEvent/get" => { ids => [$id], properties => ['duration'] },
    ]])->single_sentence("CalendarEvent/get")->arguments->{list}[0];
    # Server may normalise PT90M → PT1H30M; accept either
    ok(
      ($got->{duration} // '') =~ /^PT(90M|1H30M)$/,
      "duration round-trips (got " . ($got->{duration} // 'undef') . ")"
    );
  };

  subtest "Replace recurrenceRule (whole object)" => sub {
    my $res = $tester->request([[
      "CalendarEvent/set" => {
        update => {
          $id => {
            recurrenceRule => {
              frequency => 'monthly',
              count     => 3,
            },
          },
        },
      },
    ]]);
    ok($res->is_success, "update recurrenceRule");
    my $args = $res->single_sentence("CalendarEvent/set")->arguments;
    ok(exists $args->{updated}{$id}, 'event updated') or diag explain $args->{notUpdated};

    my $got = $tester->request([[
      "CalendarEvent/get" => { ids => [$id], properties => ['recurrenceRule'] },
    ]])->single_sentence("CalendarEvent/get")->arguments->{list}[0];
    is($got->{recurrenceRule}{frequency}, 'monthly', 'frequency updated');
    is($got->{recurrenceRule}{count},     3,          'count updated');
  };

  subtest "Patch recurrenceOverrides — add an override for one occurrence" => sub {
    my $res = $tester->request([[
      "CalendarEvent/set" => {
        update => {
          $id => {
            'recurrenceOverrides/2024-05-13T14:30:00' => {
              title => 'Board Meeting (Special)',
            },
          },
        },
      },
    ]]);
    ok($res->is_success, "patch recurrenceOverrides");
    my $args = $res->single_sentence("CalendarEvent/set")->arguments;
    ok(exists $args->{updated}{$id}, 'event updated') or diag explain $args->{notUpdated};

    my $got = $tester->request([[
      "CalendarEvent/get" => { ids => [$id], properties => ['recurrenceOverrides'] },
    ]])->single_sentence("CalendarEvent/get")->arguments->{list}[0];
    my $overrides = $got->{recurrenceOverrides} // {};
    ok(exists $overrides->{'2024-05-13T14:30:00'}, 'override key present');
    is($overrides->{'2024-05-13T14:30:00'}{title}, 'Board Meeting (Special)', 'override title set');
  };

  subtest "Patch recurrenceOverrides — exclude an occurrence" => sub {
    my $res = $tester->request([[
      "CalendarEvent/set" => {
        update => {
          $id => {
            'recurrenceOverrides/2024-05-20T14:30:00' => {
              excluded => \1,
            },
          },
        },
      },
    ]]);
    ok($res->is_success, "patch exclusion");
    my $args = $res->single_sentence("CalendarEvent/set")->arguments;
    ok(exists $args->{updated}{$id}, 'event updated') or diag explain $args->{notUpdated};

    my $qres = $tester->request([[
      "CalendarEvent/query" => {
        filter => {
          inCalendar => $calendar->id,
          after      => '2024-05-20T00:00:00',
          before     => '2024-05-21T00:00:00',
        },
        expandRecurrences => \1,
      },
    ]]);
    my $ids = $qres->single_sentence("CalendarEvent/query")->arguments->{ids} // [];
    is(scalar @$ids, 0, 'excluded occurrence absent from expanded query');

    my $got = $tester->request([[
      "CalendarEvent/get" => { ids => [$id], properties => ['recurrenceOverrides'] },
    ]])->single_sentence("CalendarEvent/get")->arguments->{list}[0];
    ok(exists($got->{recurrenceOverrides}{'2024-05-13T14:30:00'}),
       'earlier override still present');
  };

  subtest "Add location via pointer patch (locations/{id})" => sub {
    my $res = $tester->request([[
      "CalendarEvent/set" => {
        update => {
          $id => {
            'locations/room1' => { name => 'Conference Room 1' },
          },
        },
      },
    ]]);
    ok($res->is_success, "patch location");
    my $args = $res->single_sentence("CalendarEvent/set")->arguments;
    ok(exists $args->{updated}{$id}, 'event updated') or diag explain $args->{notUpdated};

    my $got = $tester->request([[
      "CalendarEvent/get" => { ids => [$id], properties => ['locations'] },
    ]])->single_sentence("CalendarEvent/get")->arguments->{list}[0];
    my $locs = $got->{locations} // {};
    my ($loc) = grep { ($_->{name} // '') eq 'Conference Room 1' } values %$locs;
    ok($loc, 'location with correct name found');
  };

  subtest "Update notFound returns error" => sub {
    my $res = $tester->request([[
      "CalendarEvent/set" => {
        update => { 'nosuchevent' => { title => 'Ghost' } },
      },
    ]]);
    ok($res->is_success, "request succeeds");
    my $args = $res->single_sentence("CalendarEvent/set")->arguments;
    ok($args->{notUpdated}{nosuchevent}, 'unknown id in notUpdated');
    is($args->{notUpdated}{nosuchevent}{type}, 'notFound', 'error type is notFound');
  };

  subtest "State advances after update" => sub {
    my $state_before = $account->get_state('calendarEvent');
    $tester->request([[
      "CalendarEvent/set" => {
        update => { $id => { title => 'State Check' } },
      },
    ]]);
    my $state_after = $account->get_state('calendarEvent');
    isnt($state_after, $state_before, 'state changed after update');
  };
};
