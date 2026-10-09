use jmaptest;

# draft-ietf-jmap-calendars S4: name "MUST NOT be the empty string and MUST
# NOT be greater than 255 octets in size when encoded as UTF-8".

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $calendar = $account->create_calendar;

  # 128 characters, but 256 octets in UTF-8.
  my %bad = (
    empty    => '',
    octets   => "\x{e9}" x 128,
    ascii256 => 'x' x 256,
  );

  my $res = $tester->request([[
    "Calendar/set" => {
      create => { map {; $_ => { name => $bad{$_} } } keys %bad },
    },
  ]]);
  my $args = $res->single_sentence("Calendar/set")->arguments;
  for my $case (sort keys %bad) {
    jcmp_deeply(
      $args->{notCreated}{$case},
      invalid_properties('name'),
      "create with $case name is invalidProperties",
    ) or diag explain $res->as_stripped_triples;
  }

  my $ures = $tester->request([[
    "Calendar/set" => { update => { $calendar->id => { name => '' } } },
  ]]);
  jcmp_deeply(
    $ures->single_sentence("Calendar/set")->arguments->{notUpdated}{ $calendar->id },
    invalid_properties('name'),
    'update to an empty name is invalidProperties',
  ) or diag explain $ures->as_stripped_triples;

  my $max = $tester->request([[
    "Calendar/set" => { create => { max => { name => 'y' x 255 } } },
  ]]);
  ok($max->single_sentence("Calendar/set")->arguments->{created}{max},
     'a 255-octet name is accepted')
    or diag explain $max->as_stripped_triples;
};
