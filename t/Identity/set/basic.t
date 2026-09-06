use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:submission',
  );

  my $get_res = $tester->request([[
    "Identity/get" => {},
  ]]);
  my $list = $get_res->single_sentence("Identity/get")->arguments->{list};
  ok(@$list >= 1, "at least one identity exists");
  my $id = $list->[0]{id};

  subtest "cannot create identity" => sub {
    my $res = $tester->request([[
      "Identity/set" => {
        create => {
          new1 => { email => 'test@example.com', name => 'Test' },
        },
      },
    ]]);
    ok($res->is_success, "Identity/set create");

    my $args = $res->single_sentence("Identity/set")->arguments;
    ok(!$args->{created} || !$args->{created}{new1}, "new identity not created");
    ok($args->{notCreated}{new1}, "new1 in notCreated");
  };

  subtest "cannot destroy identity" => sub {
    my $res = $tester->request([[
      "Identity/set" => {
        destroy => [$id],
      },
    ]]);
    ok($res->is_success, "Identity/set destroy");

    my $args = $res->single_sentence("Identity/set")->arguments;
    ok(!$args->{destroyed} || !grep { $_ eq $id } @{ $args->{destroyed} // [] },
       "identity not destroyed");
    ok($args->{notDestroyed}{$id}, "identity in notDestroyed");
  };

  subtest "update name" => sub {
    my $orig_res = $tester->request([[
      "Identity/get" => { ids => [$id] },
    ]]);
    my $orig_name = $orig_res->single_sentence("Identity/get")->arguments->{list}[0]{name};

    my $new_name = "Test Name " . int(rand(10000));

    my $res = $tester->request([[
      "Identity/set" => {
        update => {
          $id => { name => $new_name },
        },
      },
    ]]);
    ok($res->is_success, "Identity/set update");

    my $args = $res->single_sentence("Identity/set")->arguments;
    ok($args->{updated}{$id}, "identity updated") or diag explain $args;

    my $get_res = $tester->request([[
      "Identity/get" => { ids => [$id] },
    ]]);
    my $updated = $get_res->single_sentence("Identity/get")->arguments->{list}[0];
    is($updated->{name}, $new_name, "name was updated");

    $tester->request([[
      "Identity/set" => { update => { $id => { name => $orig_name } } },
    ]]);
  };
};
