use jmaptest;

use JMAP::TestSuite::Util qw(fetch_session);

# draft-ietf-jmap-calendars S1.5: the calendars capabilities in the session.

my $CAL   = 'urn:ietf:params:jmap:calendars';
my $AVAIL = 'urn:ietf:params:jmap:principals:availability';
my $PARSE = 'urn:ietf:params:jmap:calendars:parse';

my $UTC = re(qr/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z\z/);
# jscalendarbis S1.5.6 Duration.
my $DURATION = all(
  jstr,
  re(qr/\AP(?:\d+W)?(?:\d+D)?(?:T(?:\d+H)?(?:\d+M)?(?:\d+(?:\.\d+)?S)?)?\z/),
  re(qr/\d/),
);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities('urn:ietf:params:jmap:core', $CAL);

  my $data    = fetch_session($tester) or return;
  my $session = JSON::Typist->new->apply_types($data);
  my $caps    = $session->{capabilities};
  my $acaps   = $session->{accounts}{ $account->accountId }{accountCapabilities} // {};

  # S1.5.1: the session value "is an empty object".
  jcmp_deeply($caps->{$CAL}, {}, "$CAL session capability is an empty object");

  # S1.5.1: the account value "MUST contain" these.
  jcmp_deeply(
    $acaps->{$CAL},
    superhashof({
      maxCalendarsPerEvent     => any(undef, all(jnum, code(sub { $_[0] >= 1 && $_[0] == int $_[0] }))),
      minDateTime              => $UTC,
      maxDateTime              => $UTC,
      maxExpandedQueryDuration => $DURATION,
      maxParticipantsPerEvent  => any(undef, all(jnum, code(sub { $_[0] >= 0 && $_[0] == int $_[0] }))),
      mayCreateCalendar        => jbool,
    }),
    "$CAL account capability has its required fields",
  ) or diag explain $acaps->{$CAL};

  if (exists $acaps->{$AVAIL}) {
    # S1.5.2: maxAvailabilityDuration is required, and such an account "MUST
    # also have the urn:ietf:params:jmap:principals capability".
    jcmp_deeply($caps->{$AVAIL}, {}, "$AVAIL session capability is an empty object");
    jcmp_deeply($acaps->{$AVAIL}, superhashof({ maxAvailabilityDuration => $DURATION }),
                "$AVAIL account capability has maxAvailabilityDuration")
      or diag explain $acaps->{$AVAIL};
    ok(exists $acaps->{'urn:ietf:params:jmap:principals'},
       'the account also has urn:ietf:params:jmap:principals');
  }

  if (exists $caps->{$PARSE}) {
    # S1.5.3: "an empty object in both" places.
    jcmp_deeply($caps->{$PARSE}, {}, "$PARSE session capability is an empty object");
    jcmp_deeply($acaps->{$PARSE}, any(undef, {}), "$PARSE account capability, if any, is an empty object");
  }
};
