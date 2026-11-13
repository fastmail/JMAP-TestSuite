use jmaptest;

attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
    'urn:ietf:params:jmap:quota',
  );

  my $res = $tester->request([[ "Quota/get" => { ids => undef } ]]);
  ok($res->is_success, "Quota/get") or diag explain $res->response_payload;
  my %quota = map {; $_->{id} => $_ } @{ $res->single_sentence("Quota/get")->arguments->{list} };
  unless (%quota) {
    pass("server reports no quotas for this account; nothing further to check");
    return;
  }

  my $query = sub {
    my ($args, $desc) = @_;
    my $res = $tester->request([[ "Quota/query" => $args ]]);
    ok($res->is_success, "Quota/query $desc") or diag(explain($res->response_payload)), return;
    my $s = $res->single_sentence;
    is($s->name, 'Quota/query', "$desc is not an error")
      or diag(explain($s->as_stripped_pair)), return;
    return $s->arguments->{ids};
  };

  # RFC 9425 S4.4: "name" and "used" "MUST be supported for sorting". The
  # default collation is server-dependent (RFC 8620 S5.5), so allow either case.
  my %cmp = (
    name => sub {
      my ($x, $y) = map {; $_->{name} } @_;
      my ($octet, $caseless) = ($x cmp $y, lc $x cmp lc $y);
      return $octet == $caseless ? $octet : 0;
    },
    used => sub { $_[0]{used} <=> $_[1]{used} },
  );
  for my $property (sort keys %cmp) {
    for my $ascending (JSON::true, JSON::false) {
      my $desc = "sorted by $property " . ($ascending ? 'ascending' : 'descending');
      my $ids = $query->({ sort => [ { property => $property, isAscending => $ascending } ] }, $desc)
        or next;

      my @bad = grep {;
        my $c = $cmp{$property}->(map {; $quota{ $ids->[$_] } } $_ - 1, $_);
        $ascending ? $c > 0 : $c < 0;
      } 1 .. $#$ids;
      ok(!@bad, "$desc is in order") or diag explain [ map {; $quota{$_} } @$ids ];
    }
  }

  # RFC 9425 S4.4: scope and resourceType "must match the given value
  # exactly", type is contained in types, and name "contains the given string".
  my ($sample) = values %quota;
  my %filter = (
    scope        => [ $sample->{scope},        sub { $_[0]{scope} eq $sample->{scope} } ],
    resourceType => [ $sample->{resourceType}, sub { $_[0]{resourceType} eq $sample->{resourceType} } ],
    type         => [ $sample->{types}[0],     sub { grep {; $_ eq $sample->{types}[0] } @{ $_[0]{types} } } ],
    name         => [ $sample->{name},         sub { index(lc $_[0]{name}, lc $sample->{name}) >= 0 } ],
  );
  for my $prop (sort keys %filter) {
    my ($value, $match) = @{ $filter{$prop} };
    my $ids = $query->({ filter => { $prop => $value } }, "filtered by $prop") or next;
    my @want = grep {; $match->($quota{$_}) } keys %quota;
    jcmp_deeply(
      $ids,
      $prop eq 'name' ? all(superbagof($sample->{id}), subbagof(@want)) : bag(@want),
      "filter $prop returns exactly the matching quotas",
    ) or diag explain [ map {; $quota{$_} } @$ids ];
  }
};
