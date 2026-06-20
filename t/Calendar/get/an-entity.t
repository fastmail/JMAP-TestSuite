use jmaptest;

use JMAP::TestSuite::Util qw(calendar);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $calendar1 = $account->create_calendar;

  # Sanity, I guess
  ok($calendar1->id, 'calendar has an id');
  ok($calendar1->name, 'calendar has a name');
  ok($calendar1->color, 'calendar has a color');

  my $res = $tester->request([[
    "Calendar/get" => { ids => [ $calendar1->id ], },
  ]]);
  ok($res->is_success, "Calendar/get")
    or diag explain $res->response_payload;

  jcmp_deeply(
    $res->single_sentence("Calendar/get")->arguments,
    superhashof({
      accountId => jstr($account->accountId),
      state     => jstr(),
      notFound  => [],
      list      => [
        calendar({
          id        => $calendar1->id,
          name      => $calendar1->name,
          color     => $calendar1->color,
          sortOrder => 0,
          isVisible => jtrue,
        }),
      ],
    }),
    "Base response looks good",
  ) or diag explain $res->as_stripped_triples;
};
