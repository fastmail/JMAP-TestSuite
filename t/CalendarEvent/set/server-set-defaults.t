use jmaptest;

# draft-ietf-jmap-calendars S5.9: "If omitted on create, the server MUST set"
# @type, uid and created; when isOrigin it MUST set updated and bump sequence.

my $UTC = re(qr/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z\z/);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $calendar = $account->create_calendar;
  my @props = (qw(@type uid created updated isOrigin sequence title));

  my $get = sub {
    my ($id) = @_;
    my $res = $tester->request([[
      "CalendarEvent/get" => { ids => [$id], properties => \@props },
    ]]);
    return $res->single_sentence("CalendarEvent/get")->arguments->{list}[0];
  };

  subtest q{omitted @type, uid and created are set} => sub {
    my $res = $tester->request([[
      "CalendarEvent/set" => {
        create => {
          e1 => {
            calendarIds     => { $calendar->id => \1 },
            title           => "Defaults $^T.$$",
            start           => '2024-02-01T09:00:00',
            timeZone        => 'Etc/UTC',
            duration        => 'PT1H',
            showWithoutTime => \0,
            version         => '2.0',
          },
        },
      },
    ]]);
    my $created = $res->single_sentence("CalendarEvent/set")->arguments->{created}{e1};
    ok($created && $created->{id}, 'event created') or return diag explain $res->as_stripped_triples;

    # RFC 8620 S5.3: "created" includes "any properties that were omitted by
    # the client and thus set to a default by the server".
    jcmp_deeply(
      $created,
      superhashof({ uid => jstr, created => $UTC }),
      'server-set uid and created are reported in created',
    ) or diag explain $created;

    my $ev = $get->($created->{id});
    jcmp_deeply(
      $ev,
      superhashof({
        '@type' => jstr('Event'),
        uid     => all(jstr, re(qr/\S/)),
        created => $UTC,
      }),
      q{@type, uid and created were set by the server},
    ) or diag explain $ev;

    if ($ev->{isOrigin}) {
      jcmp_deeply($ev->{updated}, $UTC, 'updated was set on an origin event')
        or diag explain $ev;
    }
  };

  subtest "client updated is overridden, and created with it" => sub {
    my $res = $tester->request([[
      "CalendarEvent/set" => {
        create => {
          e2 => {
            calendarIds     => { $calendar->id => \1 },
            title           => "Times $^T.$$",
            start           => '2024-02-02T09:00:00',
            timeZone        => 'Etc/UTC',
            duration        => 'PT1H',
            showWithoutTime => \0,
            version         => '2.0',
            created         => '2098-01-01T00:00:00Z',
            updated         => '2000-01-01T00:00:00Z',
          },
        },
      },
    ]]);
    my $id = $res->single_sentence("CalendarEvent/set")->arguments->{created}{e2}{id};
    ok($id, 'event created') or return diag explain $res->as_stripped_triples;

    my $ev = $get->($id);
    unless ($ev->{isOrigin}) {
      note('event is not isOrigin; S5.9 forbids overriding updated');
      return;
    }

    isnt($ev->{updated}, '2000-01-01T00:00:00Z', 'client updated was replaced')
      or diag explain $ev;
    # S5.9: an overridden updated earlier than the client's created resets it.
    isnt($ev->{created}, '2098-01-01T00:00:00Z', 'future created was replaced')
      or diag explain $ev;
    ok(($ev->{created} // '') le ($ev->{updated} // ''), 'created is not after updated')
      or diag explain $ev;
  };

  subtest "sequence increments on a non-per-user change" => sub {
    my $event = $account->create_calendar_event({ calendar => $calendar });
    my $before = $get->($event->id);
    unless ($before->{isOrigin}) {
      note('event is not isOrigin; sequence rule does not apply');
      return;
    }

    my $res = $tester->request([[
      "CalendarEvent/set" => {
        update => { $event->id => { title => "Retitled $^T.$$" } },
      },
    ]]);
    ok(exists $res->single_sentence("CalendarEvent/set")->arguments->{updated}{ $event->id },
       'title updated') or return diag explain $res->as_stripped_triples;

    # jscalendarbis: sequence defaults to 0.
    my $after = $get->($event->id);
    is($after->{sequence} // 0, ($before->{sequence} // 0) + 1, 'sequence went up by one')
      or diag explain [ $before, $after ];
  };
};
