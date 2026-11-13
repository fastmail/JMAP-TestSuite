use jmaptest;

# draft-ietf-calext-jscalendarbis-19 S3.3.4 (recurrenceOverrides):
#
# * An exclusion "MUST be a JSON object with a single member ... The JSON
#   object MUST NOT contain any other members".
#
# * "A pointer in the PatchObject MUST NOT exactly match one of" @type,
#   method, organizerCalendarAddress, participants/*/calendarAddress,
#   privacy, prodId, recurrenceId, recurrenceIdTimeZone, sentBy, uid, and
#   "the first reference token of the pointer MUST NOT match"
#   recurrenceOverrides or recurrenceRule.  "A PatchObject violating these
#   restrictions is invalid"; RFC 8984 had such pointers ignored instead.
#
# Each such override makes the event invalid, so the create is rejected
# with invalidProperties.

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
    'excluded with title'            => { excluded => \1, title => 'x' },
    '@type'                          => { '@type' => 'Task' },
    method                           => { method => 'request' },
    organizerCalendarAddress         => { organizerCalendarAddress => 'mailto:x@example.com' },
    'participants/*/calendarAddress' => { 'participants/p1/calendarAddress' => 'mailto:x@example.com' },
    privacy                          => { privacy => 'private' },
    prodId                           => { prodId => '-//Example//EN' },
    recurrenceId                     => { recurrenceId => '2024-05-03T09:00:00' },
    recurrenceIdTimeZone             => { recurrenceIdTimeZone => 'Europe/Berlin' },
    sentBy                           => { sentBy => 'mailto:x@example.com' },
    uid                              => { uid => 'other-uid' },
    recurrenceOverrides              => { recurrenceOverrides => {} },
    recurrenceRule                   => { recurrenceRule => { frequency => 'weekly' } },
    'recurrenceRule/count'           => { 'recurrenceRule/count' => 2 },
  );

  # The patched participant must exist, or the patch fails for that instead.
  my %event_extra = (
    'participants/*/calendarAddress' => {
      participants => {
        p1 => {
          '@type'         => 'Participant',
          calendarAddress => 'mailto:p1@example.com',
          roles           => { attendee => \1 },
        },
      },
    },
  );

  my %cid = map {; $_ => s/\W+/_/gr } keys %invalid;
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
            recurrenceOverrides => { $rid => $invalid{$_} },
            %{ $event_extra{$_} // {} },
          }
        } keys %invalid
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
};
