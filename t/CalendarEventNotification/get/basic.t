use jmaptest;

# draft-ietf-jmap-calendars S7.1: a standard /get (RFC 8620 S5.1).

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $res = $tester->request([[
    "CalendarEventNotification/get" => { ids => undef },
  ]]);
  ok($res->is_success, 'CalendarEventNotification/get') or diag explain $res->response_payload;

  my $args = $res->single_sentence("CalendarEventNotification/get")->arguments;
  jcmp_deeply(
    $args,
    {
      accountId => jstr($account->accountId),
      state     => jstr,
      list      => ignore(),
      notFound  => [],
    },
    'response has the standard /get arguments',
  ) or diag explain $res->as_stripped_triples;

  for my $n (@{ $args->{list} // [] }) {
    # S7: the CalendarEventNotification properties.
    jcmp_deeply(
      $n,
      superhashof({
        id              => jstr,
        created         => jstr,
        changedBy       => superhashof({ name => jstr, email => any(undef, jstr) }),
        type            => any(map {; jstr($_) } qw(created updated destroyed)),
        calendarEventId => jstr,
        event           => superhashof({}),
      }),
      'notification has the required properties',
    ) or diag explain $n;
  }

  my $nres = $tester->request([[
    "CalendarEventNotification/get" => { ids => [ 'no-such-notification' ] },
  ]]);
  jcmp_deeply(
    $nres->single_sentence("CalendarEventNotification/get")->arguments,
    superhashof({ list => [], notFound => [ 'no-such-notification' ] }),
    'unknown id is in notFound',
  ) or diag explain $nres->as_stripped_triples;
};
