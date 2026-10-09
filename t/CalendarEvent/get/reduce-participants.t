use jmaptest;

# draft-ietf-jmap-calendars S5.7: with reduceParticipants "only participants
# with the owner role or corresponding to the user's participant identities
# will be returned" in the base event and any recurrence overrides.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $ires = $tester->request([[ "ParticipantIdentity/get" => { ids => undef } ]]);
  my $identities = eval { $ires->single_sentence("ParticipantIdentity/get")->arguments->{list} };
  my ($identity) = @{ $identities // [] };
  unless ($identity && $identity->{calendarAddress}) {
    plan skip_all => 'no ParticipantIdentity to own the event';
    return;
  }
  my $me = $identity->{calendarAddress};

  my $rid = '2024-06-02T09:00:00';
  my %attendee = (
    '@type' => 'Participant',
    roles   => { attendee => \1 },
  );
  my $event = $account->create_calendar_event({
    start          => '2024-06-01T09:00:00',
    timeZone       => 'Etc/UTC',
    recurrenceRule => { frequency => 'daily', count => 3 },
    participants   => {
      me => { '@type' => 'Participant', calendarAddress => $me,
              roles => { owner => \1, attendee => \1 } },
      a1 => { %attendee, calendarAddress => 'mailto:a1@example.com' },
      a2 => { %attendee, calendarAddress => 'mailto:a2@example.com' },
    },
    recurrenceOverrides => {
      $rid => { 'participants/a1/participationStatus' => 'declined' },
    },
  });

  my $res = $tester->request([[
    "CalendarEvent/get" => {
      ids                => [ $event->id ],
      properties         => [qw(participants recurrenceOverrides)],
      reduceParticipants => \1,
    },
  ]]);
  my $ev = $res->single_sentence("CalendarEvent/get")->arguments->{list}[0];
  ok($ev, 'got the event') or return diag explain $res->as_stripped_triples;

  my @kept = map {; $_->{calendarAddress} } values %{ $ev->{participants} // {} };
  jcmp_deeply(\@kept, [ $me ], 'only the owner participant is returned')
    or diag explain $ev;

  # An override may patch participants/a1/... or replace the whole map.
  my $names_a1 = sub {
    my ($ov) = @_;
    return 1 if grep { m{\Aparticipants/a1(?:/|\z)} } keys %$ov;
    return 1 if grep { ($_->{calendarAddress} // '') eq 'mailto:a1@example.com' }
                values %{ $ov->{participants} // {} };
    return 0;
  };

  ok(!$names_a1->($ev->{recurrenceOverrides}{$rid} // {}),
     'override does not name a removed participant')
    or diag explain $ev;

  my $full = $tester->request([[
    "CalendarEvent/get" => {
      ids        => [ $event->id ],
      properties => [qw(participants recurrenceOverrides)],
    },
  ]]);
  my $fev = $full->single_sentence("CalendarEvent/get")->arguments->{list}[0];
  is(scalar keys %{ $fev->{participants} // {} }, 3,
     'without reduceParticipants all participants are returned');
  ok($names_a1->($fev->{recurrenceOverrides}{$rid} // {}),
     'without reduceParticipants the override names a1')
    or diag explain $fev;
};
