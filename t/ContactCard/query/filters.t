use jmaptest;
use Data::GUID qw(guid_string);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:contacts',
  );

  # Distinct letter-only words, so tokenising or stemming cannot make one
  # card's value match another's.
  my @words = map {; join '', map { ('a'..'z')[rand 26] } 1 .. 10 } 1 .. 12;
  my %w;
  @w{qw(given surname full nick org email phone note street service other_name other_mail)} = @words;
  my $digits = join '', map { int rand 10 } 1 .. 9;

  my $ab = $account->create_address_book;

  # RFC 9553 S2.1: created and updated are optional, so give them values in
  # case the server does not set its own.
  my $alice = $account->create_contact_card({
    kind           => 'individual',
    created        => '2001-02-03T04:05:06Z',
    updated        => '2002-03-04T05:06:07Z',
    name           => {
      components => [
        { kind => 'given',   value => ucfirst $w{given} },
        { kind => 'surname', value => ucfirst $w{surname} },
      ],
      full => ucfirst($w{full}) . ' Person',
    },
    nicknames      => { n1 => { name => $w{nick} } },
    organizations  => { o1 => { name => ucfirst($w{org}) . ' Inc' } },
    emails         => { e1 => { address => "$w{email}\@example.com" } },
    phones         => { p1 => { number => "+1 555 $digits" } },
    notes          => { t1 => { note => "Met at the $w{note} conference" } },
    addresses      => { a1 => { components => [ { kind => 'name', value => ucfirst($w{street}) . ' Street' } ] } },
    onlineServices => { s1 => { service => ucfirst $w{service}, user => 'alice' } },
    address_book   => $ab,
  });

  my $other = $account->create_contact_card({
    kind         => 'org',
    name         => { full => ucfirst $w{other_name} },
    emails       => { e1 => { address => "$w{other_mail}\@example.org" } },
    address_book => $ab,
  });

  my $group = $account->create_contact_card({
    kind         => 'group',
    name         => { full => "Group " . ucfirst $w{other_name} },
    members      => { $alice->uid => \1 },
    address_book => $ab,
  });

  my $query = sub {
    my ($filter) = @_;
    my $res = $tester->request([[
      "ContactCard/query" => {
        filter => { operator => 'AND', conditions => [ { inAddressBook => $ab->id }, $filter ] },
      },
    ]]);
    my $s = $res->single_sentence;
    return unless $s->name eq 'ContactCard/query';
    return { map {; $_ => 1 } @{ $s->arguments->{ids} } };
  };

  # RFC 9610 S3.3.1: these compare "exactly", or by set membership.
  my %exact = (
    uid       => [ { uid       => $alice->uid },  [ $alice ] ],
    kind      => [ { kind      => 'org' },        [ $other ] ],
    hasMember => [ { hasMember => $alice->uid },  [ $group ] ],
  );

  for my $prop (sort keys %exact) {
    my ($filter, $want) = @{ $exact{$prop} };
    my $got = $query->($filter);
    jcmp_deeply(
      [ sort keys %{ $got // {} } ],
      [ sort map {; $_->id } @$want ],
      "filter $prop matches exactly the right cards",
    ) or diag explain $got;
  }

  # RFC 9610 S3.3.1 leaves text matching loose, so require only that the
  # matching card is found and the clearly different one is not.
  my %text = (
    text           => $w{note},
    name           => ucfirst($w{full}) . ' Person',
    'name/given'   => ucfirst $w{given},
    'name/surname' => ucfirst $w{surname},
    nickname       => $w{nick},
    organization   => ucfirst $w{org},
    email          => "$w{email}\@example.com",
    phone          => $digits,
    note           => $w{note},
    address        => ucfirst $w{street},
    onlineService  => ucfirst $w{service},
  );

  for my $prop (sort keys %text) {
    my $got = $query->({ $prop => $text{$prop} });
    ok($got && $got->{ $alice->id },  "filter $prop finds the matching card")
      or diag explain $got;
    ok($got && !$got->{ $other->id }, "filter $prop leaves out a card that does not match")
      or diag explain $got;
  }

  subtest "an empty FilterCondition is always true" => sub {
    my $got = $query->({});
    jcmp_deeply(
      [ sort keys %{ $got // {} } ],
      [ sort map {; $_->id } $alice, $other, $group ],
      "empty condition matches every card",
    ) or diag explain $got;
  };

  subtest "properties in one FilterCondition are ANDed" => sub {
    my $got = $query->({ 'name/given' => ucfirst($w{given}), email => "$w{email}\@example.com" });
    jcmp_deeply([ keys %{ $got // {} } ], [ $alice->id ], "both conditions true")
      or diag explain $got;

    $got = $query->({ 'name/given' => ucfirst($w{given}), email => "$w{other_mail}\@example.org" });
    jcmp_deeply($got, {}, "one condition false matches nothing")
      or diag explain $got;
  };

  subtest "created and updated dates" => sub {
    my $get = $tester->request([[
      "ContactCard/get" => { ids => [ $alice->id ], properties => [ 'created', 'updated' ] },
    ]]);
    my $card = $get->single_sentence("ContactCard/get")->arguments->{list}[0];

    for my $prop (qw(created updated)) {
      my $when = $card->{$prop};
      unless (defined $when) {
        note("card has no $prop date (RFC 9553 S2.1: optional); skipping its filters");
        next;
      }

      # RFC 9610 S3.3.1: "before" is strict; "after" is "the same or after".
      my $got = $query->({ "${prop}After" => "$when", uid => $alice->uid });
      ok($got && $got->{ $alice->id }, "${prop}After its own $prop matches") or diag explain $got;

      $got = $query->({ "${prop}Before" => "$when", uid => $alice->uid });
      jcmp_deeply($got, {}, "${prop}Before its own $prop does not match") or diag explain $got;

      $got = $query->({ "${prop}After" => '2999-01-01T00:00:00Z' });
      jcmp_deeply($got, {}, "${prop}After the far future matches nothing") or diag explain $got;

      $got = $query->({ "${prop}Before" => '2999-01-01T00:00:00Z', uid => $alice->uid });
      ok($got && $got->{ $alice->id }, "${prop}Before the far future matches") or diag explain $got;
    }
  };
};
