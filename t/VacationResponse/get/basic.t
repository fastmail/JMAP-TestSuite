use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:vacationresponse',
  );

  my $res = $tester->request([[
    "VacationResponse/get" => {},
  ]]);
  ok($res->is_success, "VacationResponse/get") or diag explain $res->response_payload;

  my $args = $res->single_sentence("VacationResponse/get")->arguments;
  ok(defined $args->{state}, "has state");

  my @list = @{ $args->{list} };
  is(scalar @list, 1, "exactly one VacationResponse");

  jcmp_deeply(
    $list[0],
    superhashof({
      id        => 'singleton',
      isEnabled => ignore(),
    }),
    "singleton has required fields",
  ) or diag explain $list[0];

  subtest "fetch by id" => sub {
    my $res = $tester->request([[
      "VacationResponse/get" => { ids => ['singleton'] },
    ]]);
    ok($res->is_success, "VacationResponse/get by id");
    my $args2 = $res->single_sentence("VacationResponse/get")->arguments;
    is(scalar @{ $args2->{list} }, 1, "got singleton");
    is($args2->{list}[0]{id}, 'singleton', "correct id");
  };
};
