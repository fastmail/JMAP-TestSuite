use jmaptest;

# draft-ietf-jmap-calendars S5.9: a null for "any optional JSCalendar Event
# property on create ... MUST be treated the same as omitting the property".

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $calendar = $account->create_calendar;

  # jscalendarbis S4: the defaults of these optional properties, if any.
  my %default = (
    description    => '',
    priority       => 0,
    freeBusyStatus => 'busy',
    locations      => undef,
    keywords       => undef,
    recurrenceRule => undef,
    alerts         => undef,
    color          => undef,
  );

  my $res = $tester->request([[
    "CalendarEvent/set" => {
      create => {
        e1 => {
          calendarIds     => { $calendar->id => \1 },
          title           => "nulls $^T.$$",
          start           => '2024-05-01T09:00:00',
          timeZone        => 'Etc/UTC',
          duration        => 'PT1H',
          showWithoutTime => \0,
          version         => '2.0',
          map {; $_ => undef } keys %default,
        },
      },
    },
  ]]);
  my $args = $res->single_sentence("CalendarEvent/set")->arguments;
  my $id = $args->{created}{e1}{id};
  ok($id, 'event with null optional properties is created')
    or return diag explain $res->as_stripped_triples;

  my $gres = $tester->request([[
    "CalendarEvent/get" => { ids => [$id], properties => [ keys %default ] },
  ]]);
  my $ev = $gres->single_sentence("CalendarEvent/get")->arguments->{list}[0];

  for my $p (sort keys %default) {
    my $want = $default{$p};
    ok(
      !defined $ev->{$p} || (defined $want && $ev->{$p} eq $want),
      "$p is absent, null or its default",
    ) or diag explain $ev;
  }
};
