use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:vacationresponse',
  );

  # Get current state to restore later
  my $orig_res = $tester->request([[
    "VacationResponse/get" => {},
  ]]);
  my $orig = $orig_res->single_sentence("VacationResponse/get")->arguments->{list}[0];

  subtest "enable vacation response" => sub {
    my $res = $tester->request([[
      "VacationResponse/set" => {
        update => {
          singleton => {
            isEnabled => jtrue(),
            subject   => 'I am away',
            textBody  => 'I will reply when I return.',
          },
        },
      },
    ]]);
    ok($res->is_success, "VacationResponse/set enable") or diag explain $res->response_payload;

    my $args = $res->single_sentence("VacationResponse/set")->arguments;
    ok($args->{updated}{singleton}, "singleton updated") or diag explain $args;
    ok(!$args->{notUpdated}{singleton}, "no notUpdated error");

    my $get_res = $tester->request([[
      "VacationResponse/get" => {},
    ]]);
    my $vr = $get_res->single_sentence("VacationResponse/get")->arguments->{list}[0];
    ok($vr->{isEnabled}, "isEnabled is true");
    is($vr->{subject},  'I am away',                   "subject updated");
    is($vr->{textBody}, 'I will reply when I return.', "textBody updated");
  };

  subtest "cannot create vacation response" => sub {
    my $res = $tester->request([[
      "VacationResponse/set" => {
        create => {
          new1 => { isEnabled => jtrue() },
        },
      },
    ]]);
    ok($res->is_success, "request succeeded");
    my $args = $res->single_sentence("VacationResponse/set")->arguments;
    ok($args->{notCreated}{new1}, "create is forbidden");
  };

  subtest "cannot destroy vacation response" => sub {
    my $res = $tester->request([[
      "VacationResponse/set" => {
        destroy => ['singleton'],
      },
    ]]);
    ok($res->is_success, "request succeeded");
    my $args = $res->single_sentence("VacationResponse/set")->arguments;
    ok($args->{notDestroyed}{singleton}, "destroy is forbidden");
  };

  $tester->request([[
    "VacationResponse/set" => {
      update => {
        singleton => {
          isEnabled => $orig->{isEnabled} ? jtrue() : jfalse(),
          subject   => $orig->{subject},
          textBody  => $orig->{textBody},
          htmlBody  => $orig->{htmlBody},
        },
      },
    },
  ]]);
};
