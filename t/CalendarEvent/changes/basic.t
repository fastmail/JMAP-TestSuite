use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  subtest "No changes returns same state" => sub {
    my $state = $account->get_state('calendarEvent');

    my $res = $tester->request([[
      "CalendarEvent/changes" => { sinceState => $state },
    ]]);
    ok($res->is_success, "CalendarEvent/changes") or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("CalendarEvent/changes")->arguments,
      superhashof({
        accountId      => jstr($account->accountId),
        oldState       => jstr($state),
        newState       => jstr($state),
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [],
        destroyed      => [],
      }),
      "no-changes response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "Created event shows up in created" => sub {
    my $state = $account->get_state('calendarEvent');

    my $event = $account->create_calendar_event;

    my $res = $tester->request([[
      "CalendarEvent/changes" => { sinceState => $state },
    ]]);
    ok($res->is_success, "CalendarEvent/changes") or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("CalendarEvent/changes")->arguments,
      superhashof({
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [ $event->id ],
        updated        => [],
        destroyed      => [],
      }),
      "created response looks good",
    );
  };

  subtest "Updated event shows up in updated" => sub {
    my $event = $account->create_calendar_event;
    my $state = $account->get_state('calendarEvent');

    $tester->request([[
      "CalendarEvent/set" => {
        update => { $event->id => { title => 'Changes Test Updated' } },
      },
    ]]);

    my $res = $tester->request([[
      "CalendarEvent/changes" => { sinceState => $state },
    ]]);
    ok($res->is_success, "CalendarEvent/changes") or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("CalendarEvent/changes")->arguments,
      superhashof({
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [ $event->id ],
        destroyed      => [],
      }),
      "updated response looks good",
    );
  };

  subtest "Destroyed event shows up in destroyed" => sub {
    my $event = $account->create_calendar_event;
    my $state = $account->get_state('calendarEvent');

    $tester->request([[
      "CalendarEvent/set" => { destroy => [ $event->id ] },
    ]]);

    my $res = $tester->request([[
      "CalendarEvent/changes" => { sinceState => $state },
    ]]);
    ok($res->is_success, "CalendarEvent/changes") or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("CalendarEvent/changes")->arguments,
      superhashof({
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [],
        destroyed      => [ $event->id ],
      }),
      "destroyed response looks good",
    );
  };
};
