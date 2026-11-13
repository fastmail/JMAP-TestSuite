use jmaptest;

# draft-ietf-jmap-calendars S7.3: "Only destroy is supported; any attempt to
# create/update MUST be rejected with a forbidden SetError."

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $event = $account->create_calendar_event;

  my $res = $tester->request([[
    "CalendarEventNotification/set" => {
      create => {
        n1 => {
          type            => 'created',
          calendarEventId => $event->id,
          changedBy       => { name => 'Someone', email => undef },
          event           => { '@type' => 'Event', title => 'Fake' },
        },
      },
    },
  ]]);
  jcmp_deeply(
    $res->single_sentence("CalendarEventNotification/set")->arguments->{notCreated}{n1},
    superhashof({ type => 'forbidden' }),
    'create is rejected with forbidden',
  ) or diag explain $res->as_stripped_triples;
};
