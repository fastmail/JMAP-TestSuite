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

  # RFC 8621 S8: isEnabled is "Boolean", fromDate/toDate "UTCDate|null",
  # and subject/textBody/htmlBody "String|null".
  my $utc_date = re(qr/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d*[1-9])?Z\z/);
  jcmp_deeply(
    $list[0],
    superhashof({
      id        => 'singleton',
      isEnabled => jbool(),
      fromDate  => any(undef, $utc_date),
      toDate    => any(undef, $utc_date),
      subject   => any(undef, jstr()),
      textBody  => any(undef, jstr()),
      htmlBody  => any(undef, jstr()),
    }),
    "singleton has every property, with the right types",
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
