use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:vacationresponse',
  );

  my $get = sub {
    $tester->request([[ "VacationResponse/get" => {} ]])
      ->single_sentence("VacationResponse/get")->arguments->{list}[0];
  };
  my $set = sub {
    my ($patch) = @_;
    my $res = $tester->request([[
      "VacationResponse/set" => { update => { singleton => $patch } },
    ]]);
    ok($res->is_success, "VacationResponse/set") or diag explain $res->response_payload;
    my $args = $res->single_sentence("VacationResponse/set")->arguments;
    ok(exists $args->{updated}{singleton}, "singleton updated") or diag explain $args;
  };

  my $orig = $get->();

  # RFC 8621 S8: fromDate and toDate are "UTCDate|null"; isEnabled stays
  # false so no auto-reply goes out.
  subtest "set dates" => sub {
    $set->({
      isEnabled => jfalse(),
      fromDate  => '2040-01-02T03:04:05Z',
      toDate    => '2040-02-03T04:05:06Z',
    });
    jcmp_deeply(
      $get->(),
      superhashof({
        fromDate => '2040-01-02T03:04:05Z',
        toDate   => '2040-02-03T04:05:06Z',
      }),
      "dates read back as set",
    );
  };

  subtest "clear dates" => sub {
    $set->({ fromDate => undef, toDate => undef });
    jcmp_deeply(
      $get->(),
      superhashof({ fromDate => undef, toDate => undef }),
      "dates read back as null",
    );
  };

  $tester->request([[
    "VacationResponse/set" => {
      update => {
        singleton => {
          isEnabled => $orig->{isEnabled} ? jtrue() : jfalse(),
          map {; $_ => $orig->{$_} } qw(fromDate toDate subject textBody htmlBody),
        },
      },
    },
  ]]);
};
