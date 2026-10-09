use jmaptest;

# draft-ietf-jmap-calendars S4.3: a default change refused for policy reasons
# "MUST be ignored" with "No error"; changed objects "MUST be reported in
# either the created or updated argument".

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $defaults = sub {
    my $res = $tester->request([[
      "Calendar/get" => { ids => undef, properties => [qw(id isDefault)] },
    ]]);
    return [ map {; $_->{id} } grep { $_->{isDefault} }
             @{ $res->single_sentence("Calendar/get")->arguments->{list} } ];
  };

  my ($original) = @{ $defaults->() };
  my $cal1 = $account->create_calendar;

  subtest "unknown id is ignored" => sub {
    my $res = $tester->request([[
      "Calendar/set" => { onSuccessSetIsDefault => 'no-such-calendar' },
    ]]);
    is($res->single_sentence->name, "Calendar/set", "no error returned")
      or diag explain $res->as_stripped_triples;
    jcmp_deeply($defaults->(), [ $original // () ], 'default unchanged');
  };

  my $current = $original;

  subtest "set an existing calendar as default" => sub {
    my $res = $tester->request([[
      "Calendar/set" => { onSuccessSetIsDefault => $cal1->id },
    ]]);
    is($res->single_sentence->name, "Calendar/set", "no error returned")
      or return diag explain $res->as_stripped_triples;
    my $args = $res->single_sentence("Calendar/set")->arguments;

    my $now = $defaults->();
    ok(@$now <= 1, 'at most one default') or diag explain $now;
    unless (grep { $_ eq $cal1->id } @$now) {
      note('server did not make cal1 the default; S4.3 permits this, skipping');
      return;
    }

    jcmp_deeply(
      $args->{updated},
      superhashof({
        $cal1->id => superhashof({ isDefault => jtrue }),
        ($current ? ($current => superhashof({ isDefault => jfalse })) : ()),
      }),
      'changed calendars reported in updated with isDefault',
    ) or diag explain $args;
    $current = $cal1->id;
  };

  subtest "set a calendar created in the same call as default" => sub {
    my $res = $tester->request([[
      "Calendar/set" => {
        create                => { c3 => { name => "Default by ref $^T.$$" } },
        onSuccessSetIsDefault => '#c3',
      },
    ]]);
    is($res->single_sentence->name, "Calendar/set", "no error returned")
      or return diag explain $res->as_stripped_triples;
    my $args = $res->single_sentence("Calendar/set")->arguments;
    my $new_id = $args->{created}{c3}{id};
    ok($new_id, 'c3 created') or return diag explain $args;

    my $now = $defaults->();
    ok(@$now <= 1, 'at most one default') or diag explain $now;
    unless (grep { $_ eq $new_id } @$now) {
      note('server did not make c3 the default; S4.3 permits this, skipping');
      return;
    }

    jcmp_deeply(
      $args,
      superhashof({
        created => { c3 => superhashof({ id => jstr($new_id), isDefault => jtrue }) },
        ($current
          ? (updated => superhashof({ $current => superhashof({ isDefault => jfalse }) }))
          : ()),
      }),
      'new default reported in created, old one in updated',
    ) or diag explain $args;
  };

  if ($original) {
    $tester->request([[
      "Calendar/set" => { onSuccessSetIsDefault => $original },
    ]]);
    jcmp_deeply($defaults->(), [ $original ], 'original default restored');
  }
};
