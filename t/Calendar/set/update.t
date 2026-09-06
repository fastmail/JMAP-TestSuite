use jmaptest;

use JMAP::TestSuite::Util qw(calendar);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $calendar = $account->create_calendar;

  subtest "Rename a calendar" => sub {
    my $res = $tester->request([[
      "Calendar/set" => {
        update => {
          $calendar->id => { name => 'Renamed Calendar' },
        },
      },
    ]]);
    ok($res->is_success, "Calendar/set update name")
      or diag explain $res->response_payload;

    my $args = $res->single_sentence("Calendar/set")->arguments;

    jcmp_deeply(
      $args,
      superhashof({
        accountId => jstr($account->accountId),
        oldState  => jstr(),
        newState  => jstr(),
        updated   => superhashof({ $calendar->id => ignore() }),
      }),
      "update response looks good",
    ) or diag explain $res->as_stripped_triples;

    ok(!$args->{notUpdated}{ $calendar->id }, 'not in notUpdated');

    my $get_res = $tester->request([[
      "Calendar/get" => { ids => [$calendar->id], properties => ['name'] },
    ]]);
    my $list = $get_res->single_sentence("Calendar/get")->arguments->{list};
    is($list->[0]{name}, 'Renamed Calendar', 'name updated');
  };

  subtest "Update color" => sub {
    my $res = $tester->request([[
      "Calendar/set" => {
        update => {
          $calendar->id => { color => '#00ff00' },
        },
      },
    ]]);
    ok($res->is_success, "Calendar/set update color")
      or diag explain $res->response_payload;

    my $args = $res->single_sentence("Calendar/set")->arguments;
    ok(exists $args->{updated}{ $calendar->id }, 'calendar updated')
      or diag explain $args->{notUpdated};

    my $get_res = $tester->request([[
      "Calendar/get" => { ids => [$calendar->id], properties => ['color'] },
    ]]);
    my $list = $get_res->single_sentence("Calendar/get")->arguments->{list};
    is(lc($list->[0]{color} // ''), '#00ff00', 'color updated');
  };

  subtest "Update notFound returns error" => sub {
    my $res = $tester->request([[
      "Calendar/set" => {
        update => {
          'notarealid' => { name => 'Ghost' },
        },
      },
    ]]);
    ok($res->is_success, "Calendar/set update unknown id");

    my $args = $res->single_sentence("Calendar/set")->arguments;
    ok($args->{notUpdated}{notarealid}, 'unknown id in notUpdated');
    is($args->{notUpdated}{notarealid}{type}, 'notFound', 'correct error type');
  };

  subtest "State advances after update" => sub {
    my $state_before = $tester->request([[
      "Calendar/get" => { ids => [] },
    ]])->single_sentence("Calendar/get")->arguments->{state};

    $tester->request([[
      "Calendar/set" => {
        update => { $calendar->id => { name => 'State Test Updated' } },
      },
    ]]);

    my $state_after = $tester->request([[
      "Calendar/get" => { ids => [] },
    ]])->single_sentence("Calendar/get")->arguments->{state};

    isnt($state_after, $state_before, 'state changed after update');
  };
};
