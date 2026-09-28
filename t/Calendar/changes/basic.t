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
    my $state = $account->get_state('calendar');

    my $res = $tester->request([[
      "Calendar/changes" => { sinceState => $state },
    ]]);
    ok($res->is_success, "Calendar/changes") or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("Calendar/changes")->arguments,
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

  subtest "Created calendar shows up in created" => sub {
    my $state = $account->get_state('calendar');

    my $calendar = $account->create_calendar;

    my $res = $tester->request([[
      "Calendar/changes" => { sinceState => $state },
    ]]);
    ok($res->is_success, "Calendar/changes") or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("Calendar/changes")->arguments,
      superhashof({
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [ $calendar->id ],
        updated        => [],
        destroyed      => [],
      }),
      "created response looks good",
    );
  };

  subtest "Updated calendar shows up in updated" => sub {
    my $calendar = $account->create_calendar;
    my $state = $account->get_state('calendar');

    $tester->request([[
      "Calendar/set" => {
        update => { $calendar->id => { name => 'Changes Test Updated' } },
      },
    ]]);

    my $res = $tester->request([[
      "Calendar/changes" => { sinceState => $state },
    ]]);
    ok($res->is_success, "Calendar/changes") or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("Calendar/changes")->arguments,
      superhashof({
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [ $calendar->id ],
        destroyed      => [],
      }),
      "updated response looks good",
    );
  };

  subtest "Destroyed calendar shows up in destroyed" => sub {
    my $calendar = $account->create_calendar;
    my $state = $account->get_state('calendar');

    $tester->request([[
      "Calendar/set" => { destroy => [ $calendar->id ] },
    ]]);

    my $res = $tester->request([[
      "Calendar/changes" => { sinceState => $state },
    ]]);
    ok($res->is_success, "Calendar/changes") or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("Calendar/changes")->arguments,
      superhashof({
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [],
        destroyed      => [ $calendar->id ],
      }),
      "destroyed response looks good",
    );
  };
};
