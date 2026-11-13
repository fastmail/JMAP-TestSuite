use jmaptest;

# draft-ietf-jmap-calendars S5.5: with onDestroyRemoveEvents, an event in the
# destroyed calendar is removed from it, and destroyed if it is in no other.
# The destruction is a change like any other: CalendarEvent/changes since
# before must list the event as destroyed (and an event that survives in
# another calendar as updated) -- the tombstone a sync client relies on.
# RFC 8620 S5.2 lets a server answer cannotCalculateChanges instead; that is
# within the spec, if inefficient, and noted rather than failed.
#
# The event in two calendars is only tried when the server allows it
# (S1.5.1: maxCalendarsPerEvent null for no limit, else at least 1).

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $session = fetch_session($tester) or return;
  my $max = $session->{accounts}{ $account->accountId }{accountCapabilities}
              {'urn:ietf:params:jmap:calendars'}{maxCalendarsPerEvent};
  my $two = !(defined $max && $max < 2);
  note("maxCalendarsPerEvent is $max; skipping the event in two calendars") unless $two;

  my $doomed = $account->create_calendar;
  my $only   = $account->create_calendar_event({ calendar => $doomed });

  my ($other, $both);
  if ($two) {
    $other = $account->create_calendar;
    $both  = $account->create_calendar_event({ calendar => $other });
    my $add = $tester->request([[
      "CalendarEvent/set" => {
        update => { $both->id => { "calendarIds/" . $doomed->id => jtrue } },
      },
    ]])->single_sentence("CalendarEvent/set")->arguments;
    unless (exists $add->{updated}{ $both->id }) {
      note("could not put an event in two calendars; skipping that part");
      undef $both;
    }
  }

  my $state = $tester->request([[ "CalendarEvent/get" => { ids => [] } ]])
                ->single_sentence("CalendarEvent/get")->arguments->{state};

  my $res = $tester->request([[
    "Calendar/set" => {
      destroy               => [ $doomed->id ],
      onDestroyRemoveEvents => jtrue,
    },
  ]]);
  jcmp_deeply(
    $res->single_sentence("Calendar/set")->arguments->{destroyed},
    [ $doomed->id ],
    "calendar destroyed",
  ) or return diag explain $res->as_stripped_triples;

  my $changes = $tester->request([[
    "CalendarEvent/changes" => { sinceState => $state },
  ]])->single_sentence;

  if ($changes->name eq 'error'
      && ($changes->arguments->{type} // '') eq 'cannotCalculateChanges') {
    note("inefficient but within the spec: cannotCalculateChanges after a calendar destroy");
    pass("cannotCalculateChanges is allowed");
    return;
  }

  my $args = $changes->arguments;
  is($changes->name, 'CalendarEvent/changes', "CalendarEvent/changes answered")
    or return diag explain $args;
  isnt($args->{newState}, $state, "the state moved");
  ok((grep { $_ eq $only->id } @{ $args->{destroyed} || [] }),
     "the event only in the calendar is destroyed") or diag explain $args;
  ok(!(grep { $_ eq $only->id } @{ $args->{created} || [] }, @{ $args->{updated} || [] }),
     "and not reported as created or updated") or diag explain $args;
  return unless $both;

  # RFC 8620 S5.2: an id may be in at most one of created, updated, destroyed
  ok((grep { $_ eq $both->id } @{ $args->{updated} || [] }),
     "the event in another calendar too is updated") or diag explain $args;
  ok(!(grep { $_ eq $both->id } @{ $args->{destroyed} || [] }),
     "and not destroyed") or diag explain $args;
};
