use jmaptest;

use Data::GUID qw(guid_string);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $calendar = $account->create_calendar;
  my $title    = "Event " . guid_string();

  my $res = $tester->request([[
    "CalendarEvent/set" => {
      create => {
        e1 => {
          calendarIds => { $calendar->id => \1 },
          title       => $title,
          start       => '2024-06-01T10:00:00',
          timeZone    => 'America/New_York',
          duration    => 'PT2H',
          showWithoutTime => \0,
          version         => '2.0',
        },
      },
    },
  ]]);
  ok($res->is_success, "CalendarEvent/set create")
    or diag explain $res->response_payload;

  my $set_args = $res->single_sentence("CalendarEvent/set")->arguments;

  jcmp_deeply(
    $set_args,
    superhashof({
      accountId => jstr($account->accountId),
      oldState  => jstr(),
      newState  => jstr(),
      created   => superhashof({ e1 => superhashof({ id => jstr() }) }),
    }),
    "CalendarEvent/set response looks good",
  ) or diag explain $res->as_stripped_triples;

  my $id = $set_args->{created}{e1}{id};
  ok($id, 'got event id');

  subtest "Verify via get" => sub {
    my $get_res = $tester->request([[
      "CalendarEvent/get" => {
        ids        => [$id],
        properties => [qw(title start timeZone duration showWithoutTime calendarIds)],
      },
    ]]);
    ok($get_res->is_success, "CalendarEvent/get");

    # showWithoutTime defaults to false and a server may omit a property at
    # its default, so absent is fine but present must be false.
    my $swt = $get_res->single_sentence("CalendarEvent/get")
                      ->arguments->{list}[0]{showWithoutTime};
    ok(!$swt, 'showWithoutTime is false or omitted');

    my $list = $get_res->single_sentence("CalendarEvent/get")->arguments->{list};
    is(scalar @$list, 1, 'got 1 event');

    jcmp_deeply(
      $list->[0],
      superhashof({
        id       => jstr($id),
        title    => jstr($title),
        start    => jstr('2024-06-01T10:00:00'),
        timeZone => jstr('America/New_York'),
        duration => jstr('PT2H'),
      }),
      "Event properties look good",
    ) or diag explain $get_res->as_stripped_triples;
  };
};
