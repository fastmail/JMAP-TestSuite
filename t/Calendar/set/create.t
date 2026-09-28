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

  subtest "Create a calendar with name only" => sub {
    my $res = $tester->request([[
      "Calendar/set" => {
        create => {
          cal1 => { name => 'Test Calendar' },
        },
      },
    ]]);
    ok($res->is_success, "Calendar/set create")
      or diag explain $res->response_payload;

    my $args = $res->single_sentence("Calendar/set")->arguments;

    jcmp_deeply(
      $args,
      superhashof({
        accountId => jstr($account->accountId),
        oldState  => jstr(),
        newState  => jstr(),
        created   => superhashof({
          cal1 => superhashof({ id => jstr() }),
        }),
      }),
      "create response looks good",
    ) or diag explain $res->as_stripped_triples;

    ok(!$args->{notCreated}{cal1}, 'cal1 not in notCreated');

    my $id = $args->{created}{cal1}{id};
    ok($id, 'got id for created calendar');

    subtest "Verify via get" => sub {
      my $get_res = $tester->request([[
        "Calendar/get" => { ids => [$id] },
      ]]);
      ok($get_res->is_success, "Calendar/get after create");

      my $list = $get_res->single_sentence("Calendar/get")->arguments->{list};
      is(scalar @$list, 1, 'got 1 calendar');
      is($list->[0]{name}, 'Test Calendar', 'name correct');
    };
  };

  subtest "Create a calendar with name and color" => sub {
    my $res = $tester->request([[
      "Calendar/set" => {
        create => {
          cal2 => {
            name  => 'Colorful Calendar',
            color => '#ff0000',
          },
        },
      },
    ]]);
    ok($res->is_success, "Calendar/set create with color")
      or diag explain $res->response_payload;

    my $args = $res->single_sentence("Calendar/set")->arguments;
    my $id = $args->{created}{cal2}{id};
    ok($id, 'got id');

    my $get_res = $tester->request([[
      "Calendar/get" => { ids => [$id], properties => ['name', 'color'] },
    ]]);
    my $list = $get_res->single_sentence("Calendar/get")->arguments->{list};
    is($list->[0]{name},              'Colorful Calendar', 'name correct');
    is(lc($list->[0]{color} // ''), '#ff0000',           'color correct');
  };

  subtest "Name is required" => sub {
    my $res = $tester->request([[
      "Calendar/set" => {
        create => {
          bad => { color => '#aabbcc' },
        },
      },
    ]]);
    ok($res->is_success, "Calendar/set create without name");

    my $args = $res->single_sentence("Calendar/set")->arguments;
    ok($args->{notCreated}{bad}, 'bad in notCreated');
    is($args->{notCreated}{bad}{type}, 'invalidProperties', 'correct error type');
    ok(!$args->{created}{bad}, 'bad not in created');
  };

  subtest "State advances after create" => sub {
    my $state_before = $tester->request([[
      "Calendar/get" => { ids => [] },
    ]])->single_sentence("Calendar/get")->arguments->{state};

    $tester->request([[
      "Calendar/set" => {
        create => { c => { name => 'State Test' } },
      },
    ]]);

    my $state_after = $tester->request([[
      "Calendar/get" => { ids => [] },
    ]])->single_sentence("Calendar/get")->arguments->{state};

    isnt($state_after, $state_before, 'state changed after create');
  };
};
