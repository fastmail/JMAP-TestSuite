use jmaptest;

use JMAP::TestSuite::Util qw(calendar_event);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $event = $account->create_calendar_event;

  ok($event->id,    'event has an id');
  ok($event->title, 'event has a title');
  ok($event->start, 'event has a start');

  my $res = $tester->request([[
    "CalendarEvent/get" => { ids => [ $event->id ] },
  ]]);
  ok($res->is_success, "CalendarEvent/get")
    or diag explain $res->response_payload;

  jcmp_deeply(
    $res->single_sentence("CalendarEvent/get")->arguments,
    superhashof({
      accountId => jstr($account->accountId),
      state     => jstr(),
      notFound  => [],
      list      => [
        calendar_event({
          id    => $event->id,
          title => $event->title,
          start => $event->start,
        }),
      ],
    }),
    "CalendarEvent/get response looks good",
  ) or diag explain $res->as_stripped_triples;
};
