use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:contacts',
  );

  my $ab = $account->create_address_book;

  # RFC 9553 S2.1: created and updated are optional, so give them distinct
  # values in an order that differs between the two and from the names.
  my @spec = (
    [ 'Bravo',   '2003-01-01T00:00:00Z', '2011-01-01T00:00:00Z' ],
    [ 'Charlie', '2001-01-01T00:00:00Z', '2012-01-01T00:00:00Z' ],
    [ 'Alpha',   '2002-01-01T00:00:00Z', '2010-01-01T00:00:00Z' ],
  );

  my @cards = map {;
    my ($given, $created, $updated) = @$_;
    $account->create_contact_card({
      name         => {
        components => [
          { kind => 'given',   value => $given },
          { kind => 'surname', value => "Sortson" },
        ],
      },
      created      => $created,
      updated      => $updated,
      address_book => $ab,
    });
  } @spec;

  my $get = $tester->request([[
    "ContactCard/get" => {
      ids        => [ map {; $_->id } @cards ],
      properties => [ qw(created updated name) ],
    },
  ]]);
  my %card = map {; $_->{id} => $_ }
    @{ $get->single_sentence("ContactCard/get")->arguments->{list} };

  my $sorted = sub {
    my ($property, $ascending) = @_;
    my $res = $tester->request([[
      "ContactCard/query" => {
        filter => { inAddressBook => $ab->id },
        sort   => [ { property => $property, isAscending => $ascending } ],
      },
    ]]);
    ok($res->is_success, "ContactCard/query sorted by $property")
      or diag explain $res->response_payload;
    return $res->single_sentence;
  };

  # RFC 9610 S3.3.2: "created" and "updated" "MUST be supported for sorting".
  for my $property (qw(created updated)) {
    for my $ascending (JSON::true, JSON::false) {
      my $dir = $ascending ? 'ascending' : 'descending';
      my $s = $sorted->($property, $ascending);
      is($s->name, 'ContactCard/query', "sort by $property $dir is supported")
        or diag(explain($s->as_stripped_pair)), next;

      my @ids = @{ $s->arguments->{ids} };
      jcmp_deeply(\@ids, bag(map {; $_->id } @cards), "all the cards are returned")
        or next;

      my @values = map {; $card{$_}{$property} } @ids;
      if (grep {; !defined } @values) {
        note("not every card has $property; cannot check the order");
        next;
      }

      my @want = sort { $ascending ? $a cmp $b : $b cmp $a } @values;
      jcmp_deeply(\@values, \@want, "cards are in $dir $property order")
        or diag explain \@values;
    }
  }

  # RFC 9610 S3.3.2: "name/given" and "name/surname" only "SHOULD" be
  # supported; RFC 8620 S5.5 then requires unsupportedSort.
  for my $property ('name/given', 'name/surname') {
    my $s = $sorted->($property, JSON::true);
    if ($s->name eq 'error') {
      jcmp_deeply(
        $s->arguments,
        superhashof({ type => 'unsupportedSort' }),
        "sort by $property is unsupportedSort",
      ) or diag explain $s->as_stripped_pair;
      next;
    }

    next unless $property eq 'name/given';
    jcmp_deeply(
      $s->arguments->{ids},
      [ map {; $_->id } @cards[2, 0, 1] ],
      "cards are in ascending given-name order",
    ) or diag explain $s->as_stripped_pair;
  }
};
