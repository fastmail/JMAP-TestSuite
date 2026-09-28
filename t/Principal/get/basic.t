use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:principals',
  );

  # RFC 8620 S5.1 lets a server answer requestTooLarge to a null "ids" once
  # there are more records than maxObjectsInGet (Cyrus has a principal per
  # user), so find one through Principal/query.
  my $qres = $tester->request([[
    "Principal/query" => { limit => 1 },
  ]]);
  ok($qres->is_success, "Principal/query") or diag explain $qres->response_payload;

  my ($id_from_query) = @{
    $qres->single_sentence("Principal/query")->arguments->{ids} // []
  };
  ok($id_from_query, "found a principal to fetch") or return;

  my $res = $tester->request([[
    "Principal/get" => { ids => [ $id_from_query ] },
  ]]);
  ok($res->is_success, "Principal/get") or diag explain $res->response_payload;

  my $args = $res->single_sentence("Principal/get")->arguments;
  ok(defined $args->{state}, "has state");
  ok(ref $args->{list} eq 'ARRAY', "list is array");

  my @list = @{ $args->{list} };
  ok(@list >= 1, "at least one principal");

  my $principal = $list[0];
  jcmp_deeply(
    $principal,
    superhashof({
      id   => jstr(),
      type => jstr(),
      name => jstr(),
    }),
    "principal has required fields",
  ) or diag explain $principal;

  my $id = $principal->{id};

  subtest "fetch by id" => sub {
    my $res = $tester->request([[
      "Principal/get" => { ids => [$id] },
    ]]);
    ok($res->is_success, "Principal/get by id");

    my $args2 = $res->single_sentence("Principal/get")->arguments;
    is(scalar @{ $args2->{list} },     1, "one result");
    is(scalar @{ $args2->{notFound} }, 0, "nothing not found");
    is($args2->{list}[0]{id}, $id, "correct principal returned");
  };

  subtest "fetch unknown id" => sub {
    my $res = $tester->request([[
      "Principal/get" => { ids => ['nonexistent-principal'] },
    ]]);
    ok($res->is_success, "Principal/get with unknown id");

    my $args3 = $res->single_sentence("Principal/get")->arguments;
    is(scalar @{ $args3->{list} },     0, "no results");
    is(scalar @{ $args3->{notFound} }, 1, "one not found");
  };
};
