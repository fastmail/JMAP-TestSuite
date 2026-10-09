use jmaptest;

# jscalendarbis S3.3.4: an exclusion "MUST NOT contain any other members" and
# some pointers MUST NOT appear in an override; "A PatchObject violating these
# restrictions is invalid".

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

  my %bad = (
    'excluded with title'  => { excluded => \1, title => 'x' },
    uid                    => { uid => 'other-uid' },
    recurrenceId           => { recurrenceId => '2024-05-03T09:00:00' },
    recurrenceRule         => { recurrenceRule => { frequency => 'weekly' } },
    'recurrenceRule/count' => { 'recurrenceRule/count' => 2 },
    recurrenceOverrides    => { recurrenceOverrides => {} },
    method                 => { method => 'request' },
    privacy                => { privacy => 'private' },
    '@type'                => { '@type' => 'Task' },
  );

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

  for my $case (sort keys %bad) {
    jcmp_deeply(
      $args->{notCreated}{ $cid{$case} },
      invalid_properties('recurrenceOverrides'),
      "override with $case is invalidProperties",
    ) or diag explain $args->{created}{ $cid{$case} } // $args->{notCreated}{ $cid{$case} };
  }
};
