use jmaptest;

# A quota has to exist to be tested, and the shared account may have none;
# pristine accounts are provisioned with one.
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

  my $res = $tester->request([[
    "Quota/get" => {},
  ]]);
  ok($res->is_success, "Quota/get") or diag explain $res->response_payload;

  my $args = $res->single_sentence("Quota/get")->arguments;
  ok(defined $args->{state}, "has state");
  ok(ref $args->{list} eq 'ARRAY', "list is array");
  ok(ref $args->{notFound} eq 'ARRAY', "notFound is array");

  my @list = @{ $args->{list} };
  unless (@list) {
    pass("server reports no quotas for this account; nothing further to check");
    return;
  }

  for my $q (@list) {
    jcmp_deeply(
      $q,
      superhashof({
        id           => jstr(),
        resourceType => jstr(),
        used         => jnum(),
        hardLimit    => jnum(),
        scope        => jstr(),
        name         => jstr(),
        types        => array_each(jstr()),
      }),
      "quota $q->{id} has required fields",
    ) or diag explain $q;
  }

  subtest "fetch by id" => sub {
    my $first_id = $list[0]{id};
    my $res = $tester->request([[
      "Quota/get" => { ids => [$first_id] },
    ]]);
    ok($res->is_success, "Quota/get by id");

    my $args2 = $res->single_sentence("Quota/get")->arguments;
    is(scalar @{ $args2->{list} },     1, "one result");
    is(scalar @{ $args2->{notFound} }, 0, "nothing not found");
    is($args2->{list}[0]{id}, $first_id, "correct quota returned");
  };

  subtest "fetch unknown id" => sub {
    my $res = $tester->request([[
      "Quota/get" => { ids => ['nonexistent-quota'] },
    ]]);
    ok($res->is_success, "Quota/get with unknown id");

    my $args3 = $res->single_sentence("Quota/get")->arguments;
    is(scalar @{ $args3->{list} },     0, "no results");
    is(scalar @{ $args3->{notFound} }, 1, "one not found");
  };
};
