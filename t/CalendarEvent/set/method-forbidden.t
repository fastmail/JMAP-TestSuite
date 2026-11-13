use jmaptest;

# draft-ietf-jmap-calendars S5.9: "The method property MUST NOT be set. Any
# attempt to do so is rejected with a standard invalidProperties SetError."

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $calendar = $account->create_calendar;

  my $res = $tester->request([[
    "CalendarEvent/set" => {
      create => {
        e1 => {
          calendarIds     => { $calendar->id => \1 },
          title           => "method $^T.$$",
          start           => '2024-05-01T09:00:00',
          timeZone        => 'Etc/UTC',
          duration        => 'PT1H',
          showWithoutTime => \0,
          version         => '2.0',
          method          => 'request',
        },
      },
    },
  ]]);
  jcmp_deeply(
    $res->single_sentence("CalendarEvent/set")->arguments->{notCreated}{e1},
    invalid_properties('method'),
    'method on create is invalidProperties',
  ) or diag explain $res->as_stripped_triples;

  my $ev = $account->create_calendar_event({ calendar => $calendar });
  my $ures = $tester->request([[
    "CalendarEvent/set" => { update => { $ev->id => { method => 'publish' } } },
  ]]);
  jcmp_deeply(
    $ures->single_sentence("CalendarEvent/set")->arguments->{notUpdated}{ $ev->id },
    invalid_properties('method'),
    'method on update is invalidProperties',
  ) or diag explain $ures->as_stripped_triples;
};
