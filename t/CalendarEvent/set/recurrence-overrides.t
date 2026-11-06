use jmaptest;

# draft-ietf-calext-jscalendarbis-15 S3.3.4 (recurrenceOverrides):
#
# * An exclusion "MUST be a JSON object with a single member ... The JSON
#   object MUST NOT contain any other members", so an override of
#   { excluded: true, title: ... } is invalid.
#
# * "A pointer in the PatchObject MUST be ignored if it starts with one of the
#   following prefixes: @type, method, organizerCalendarAddress,
#   participants/*/calendarAddress, privacy, prodId, recurrenceId,
#   recurrenceIdTimeZone, recurrenceOverrides, recurrenceRule, relatedTo, uid"
#   (RFC 8984 S4.3.5 likewise).  Such an override is not invalid, so the
#   create succeeds.
#
# draft-ietf-jmap-calendars-26 does not change this for those pointers, with
# one exception: S5 says a CalendarEvent "MUST NOT have a method property" and
# S5.9 says "The method property MUST NOT be set.  Any attempt to do so is
# rejected with a standard invalidProperties SetError".  Whether a "method"
# pointer in an override is such an attempt is open, so for it either outcome
# is accepted.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $calendar = $account->create_calendar;
  my $rid = '2024-05-02T09:00:00';

  my %invalid = (
    'excluded with title'  => { excluded => \1, title => 'x' },
  );

  my %ignored = (
    uid                    => { uid => 'other-uid' },
    recurrenceId           => { recurrenceId => '2024-05-03T09:00:00' },
    recurrenceRule         => { recurrenceRule => { frequency => 'weekly' } },
    'recurrenceRule/count' => { 'recurrenceRule/count' => 2 },
    recurrenceOverrides    => { recurrenceOverrides => {} },
    privacy                => { privacy => 'private' },
    '@type'                => { '@type' => 'Task' },
  );

  my %either = (
    method                 => { method => 'request' },
  );

  my %bad = (%invalid, %ignored, %either);

  my %cid = map {; $_ => s/\W+/_/gr } keys %bad;
  my $res = $tester->request([[
    "CalendarEvent/set" => {
      create => {
        map {;
          $cid{$_} => {
            calendarIds         => { $calendar->id => \1 },
            title               => "override $_",
            start               => '2024-05-01T09:00:00',
            timeZone            => 'Etc/UTC',
            duration            => 'PT1H',
            showWithoutTime     => \0,
            version             => '2.0',
            recurrenceRule      => { frequency => 'daily', count => 3 },
            recurrenceOverrides => { $rid => $bad{$_} },
          }
        } keys %bad
      },
    },
  ]]);
  my $args = $res->single_sentence("CalendarEvent/set")->arguments;

  for my $case (sort keys %invalid) {
    jcmp_deeply(
      $args->{notCreated}{ $cid{$case} },
      invalid_properties('recurrenceOverrides'),
      "override with $case is invalidProperties",
    ) or diag explain $args->{created}{ $cid{$case} } // $args->{notCreated}{ $cid{$case} };
  }

  for my $case (sort keys %ignored) {
    ok(
      $args->{created}{ $cid{$case} },
      "override with ignored pointer $case: create succeeds",
    ) or diag explain $args->{notCreated}{ $cid{$case} };
  }

  for my $case (sort keys %either) {
    my $id = $cid{$case};
    if ($args->{created}{$id}) {
      pass("override with $case: create succeeds (pointer ignored)");
    } else {
      jcmp_deeply(
        $args->{notCreated}{$id},
        invalid_properties('recurrenceOverrides'),
        "override with $case: rejected as invalidProperties",
      ) or diag explain $args->{notCreated}{$id};
    }
  }
};
