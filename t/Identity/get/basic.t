use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:submission',
  );

  my $res = $tester->request([[
    "Identity/get" => {},
  ]]);
  ok($res->is_success, "Identity/get") or diag explain $res->response_payload;

  my $args = $res->single_sentence("Identity/get")->arguments;
  ok(defined $args->{state}, "has state");
  ok(ref $args->{list} eq 'ARRAY', "list is array");

  my @list = @{ $args->{list} };
  ok(@list >= 1, "at least one identity");

  my $first = $list[0];
  jcmp_deeply(
    $first,
    superhashof({
      id        => jstr(),
      mayDelete => jfalse(),
      email     => jstr(),
    }),
    "identity has required fields",
  ) or diag explain $first;

  my $id = $first->{id};

  subtest "fetch by id" => sub {
    my $res = $tester->request([[
      "Identity/get" => { ids => [$id] },
    ]]);
    ok($res->is_success, "Identity/get by id");

    my $args2 = $res->single_sentence("Identity/get")->arguments;
    is(scalar @{ $args2->{list} },     1, "one result");
    is(scalar @{ $args2->{notFound} }, 0, "nothing not found");
    is($args2->{list}[0]{id}, $id, "correct identity returned");
  };

  subtest "fetch unknown id" => sub {
    my $res = $tester->request([[
      "Identity/get" => { ids => ['nonexistent'] },
    ]]);
    ok($res->is_success, "Identity/get with unknown id");

    my $args3 = $res->single_sentence("Identity/get")->arguments;
    is(scalar @{ $args3->{list} },     0, "no results");
    is(scalar @{ $args3->{notFound} }, 1, "one not found");
    is($args3->{notFound}[0], 'nonexistent', "correct not-found id");
  };
};
