use jmaptest;

use JMAP::TestSuite::Util qw(fetch_session);

# draft-ietf-jmap-calendars S5.11: with expandRecurrences "the filter MUST be
# just a FilterCondition (not a FilterOperator) and MUST include both a
# before and after property".

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $calendar = $account->create_calendar;
  $account->create_calendar_event({
    calendar       => $calendar,
    start          => '2024-04-01T09:00:00',
    recurrenceRule => { frequency => 'daily' },
  });

  my $after  = '2024-04-01T00:00:00';
  my $before = '2024-04-03T00:00:00';

  my %bad = (
    'no before' => { inCalendar => $calendar->id, after => $after },
    'no after'  => { inCalendar => $calendar->id, before => $before },
    'no range'  => { inCalendar => $calendar->id },
    'FilterOperator' => {
      operator   => 'AND',
      conditions => [
        { inCalendar => $calendar->id },
        { after => $after, before => $before },
      ],
    },
  );

  for my $case (sort keys %bad) {
    my $res = $tester->request([[
      "CalendarEvent/query" => { filter => $bad{$case}, expandRecurrences => \1 },
    ]]);
    my $s = $res->single_sentence;
    is($s->name, 'error', "$case: rejected with an error")
      or diag explain $res->as_stripped_triples;
    # RFC 8620 S5.5 offers both for a filter the server will not process.
    jcmp_deeply(
      $s->arguments,
      superhashof({ type => any(qw(invalidArguments unsupportedFilter)) }),
      "$case: invalidArguments or unsupportedFilter",
    ) or diag explain $s->arguments;
  }

  subtest "expandDurationTooLarge" => sub {
    my $session = fetch_session($tester) or return;
    my $max = $session->{accounts}{ $account->accountId }{accountCapabilities}
                {'urn:ietf:params:jmap:calendars'}{maxExpandedQueryDuration};

    # jscalendarbis S1.5.6: only weeks and days carry the calendar part.
    my ($w, $d) = (defined $max ? $max : '') =~ /\AP(?:(\d+)W)?(?:(\d+)D)?/;
    my $days = ($w // 0) * 7 + ($d // 0) + 1;
    if (!defined $max || $days > 30 * 365) {
      note('no usable maxExpandedQueryDuration; skipping');
      return;
    }

    my $res = $tester->request([[
      "CalendarEvent/query" => {
        filter => {
          inCalendar => $calendar->id,
          after      => '2000-01-01T00:00:00',
          before     => '2031-01-01T00:00:00',
        },
        expandRecurrences => \1,
      },
    ]]);
    # S5.11 lists expandDurationTooLarge as an error that "may be returned".
    my $s = $res->single_sentence;
    if ($s->name ne 'error') {
      note("server expanded a range over its maxExpandedQueryDuration $max");
      return;
    }
    is($s->arguments->{type}, 'expandDurationTooLarge', "a range over $max is expandDurationTooLarge")
      or diag explain $s->arguments;
  };
};
