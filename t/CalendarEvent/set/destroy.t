use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $event = $account->create_calendar_event;
  ok($event->id, 'created event');

  my $res = $tester->request([[
    "CalendarEvent/set" => {
      destroy => [ $event->id ],
    },
  ]]);
  ok($res->is_success, "CalendarEvent/set destroy")
    or diag explain $res->response_payload;

  my $set_args = $res->single_sentence("CalendarEvent/set")->arguments;

  ok(grep { $_ eq $event->id } @{ $set_args->{destroyed} // [] },
    'event id in destroyed list');

  ok(!$set_args->{notDestroyed}{ $event->id }, 'no notDestroyed entry');

  subtest "Event no longer returned by get" => sub {
    my $get_res = $tester->request([[
      "CalendarEvent/get" => { ids => [ $event->id ] },
    ]]);
    ok($get_res->is_success, "CalendarEvent/get after destroy");

    my $args = $get_res->single_sentence("CalendarEvent/get")->arguments;
    is(scalar @{ $args->{list} }, 0, 'no events returned');
    ok(grep { $_ eq $event->id } @{ $args->{notFound} // [] },
      'event id in notFound');
  };
};
