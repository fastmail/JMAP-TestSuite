use jmaptest;

use JMAP::TestSuite::Util qw(calendar_event);

attr pristine  => 1;
attr pool_pairs => 1;

test {
  my ($self) = @_;

  my ($from_account, $to_account) = $self->pool_account_pair;
  my $from_tester = $from_account->tester;
  my $to_tester   = $to_account->tester;

  $from_tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  # Skip unless the destination is usable for calendars at all: a Cyrus pool
  # pair shares mail, but Calendar/get on the other account is
  # accountNotSupportedByMethod.
  my $probe = $from_tester->request([[
    "Calendar/get" => { accountId => $to_account->accountId },
  ]])->single_sentence;

  if ($probe->name eq 'error') {
    pass("destination account is not usable for calendars ("
       . ($probe->arguments->{type} // 'unknown error')
       . "); skipping cross-account CalendarEvent/copy");
    return;
  }

  # Skip unless there is a writable calendar there too; Cyrus shows the
  # grantee only a Default calendar with mayWriteAll false.
  unless (grep { $_->{myRights}{mayWriteAll} }
          @{ $probe->arguments->{list} // [] }) {
    pass("no writable calendar in the destination account; "
       . "skipping cross-account CalendarEvent/copy");
    return;
  }

  my $src_event = $from_account->create_calendar_event({
    title => "Cross-account test event $$",
  });

  my $dest_cal = $to_account->create_calendar;

  my $res = $from_tester->request([[
    "CalendarEvent/copy" => {
      fromAccountId => $from_account->accountId,
      accountId     => $to_account->accountId,
      create => {
        c1 => {
          id          => $src_event->id,
          calendarIds => { $dest_cal->id => JSON::true },
        },
      },
    },
  ]]);
  ok($res->is_success, "CalendarEvent/copy") or diag explain $res->response_payload;

  jcmp_deeply(
    $res->single_sentence("CalendarEvent/copy")->arguments,
    {
      fromAccountId => jstr($from_account->accountId),
      accountId     => jstr($to_account->accountId),
      oldState      => jstr(),
      newState      => jstr(),
      created       => { c1 => superhashof({ id => jstr() }) },
      notCreated    => undef,
    },
    "CalendarEvent/copy response looks right",
  ) or diag explain $res->as_stripped_triples;

  my $new_id = $res->single_sentence("CalendarEvent/copy")->arguments->{created}{c1}{id};

  my $verify = $to_tester->request([[
    "CalendarEvent/get" => {
      accountId => $to_account->accountId,
      ids       => [ $new_id ],
    },
  ]]);
  jcmp_deeply(
    $verify->single_sentence("CalendarEvent/get")->arguments->{list}[0],
    calendar_event({
      id          => $new_id,
      title       => $src_event->title,
      calendarIds => { $dest_cal->id => JSON::true },
    }),
    "copied event has correct title and is in destination calendar",
  ) or diag explain $verify->as_stripped_triples;

  my $orig = $from_tester->request([[
    "CalendarEvent/get" => {
      accountId => $from_account->accountId,
      ids       => [ $src_event->id ],
    },
  ]]);
  ok(
    $orig->single_sentence("CalendarEvent/get")->arguments->{list}[0],
    "original event still exists in source account",
  );
};
