use jmaptest;

# draft-ietf-jmap-calendars S4: isDefault is server-set. RFC 8620 S5.3: a
# server-set property in an update that differs from the current value "MUST
# be rejected with an invalidProperties SetError".

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $calendar = $account->create_calendar;

  subtest "create with isDefault" => sub {
    my $res = $tester->request([[
      "Calendar/set" => {
        create => { c1 => { name => "isDefault $^T.$$", isDefault => \1 } },
      },
    ]]);
    jcmp_deeply(
      $res->single_sentence("Calendar/set")->arguments->{notCreated}{c1},
      invalid_properties('isDefault'),
      'isDefault on create is invalidProperties',
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "update with isDefault" => sub {
    my $res = $tester->request([[
      "Calendar/set" => { update => { $calendar->id => { isDefault => \1 } } },
    ]]);
    jcmp_deeply(
      $res->single_sentence("Calendar/set")->arguments->{notUpdated}{ $calendar->id },
      invalid_properties('isDefault'),
      'setting isDefault true is invalidProperties',
    ) or diag explain $res->as_stripped_triples;

    # RFC 8620 S5.3: a server-set property "MAY be included in the patch if
    # their value is identical to the current server value".
    my $current = $tester->request([[
      "Calendar/get" => { ids => [ $calendar->id ], properties => ['isDefault'] },
    ]])->single_sentence("Calendar/get")->arguments->{list}[0]{isDefault};
    my $same = $tester->request([[
      "Calendar/set" => {
        update => { $calendar->id => { isDefault => $current ? \1 : \0 } },
      },
    ]]);
    ok(exists $same->single_sentence("Calendar/set")->arguments->{updated}{ $calendar->id },
       'sending the current isDefault value is accepted')
      or diag explain $same->as_stripped_triples;
  };
};
