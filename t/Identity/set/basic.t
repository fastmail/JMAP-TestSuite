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
  # RFC 8621 S6 doesn't require an account to have any Identity.
  my $id = @$list ? $list->[0]{id} : undef;

  subtest "create identity" => sub {
    my $res = $tester->request([[
      "Identity/set" => {
        create => {
          new1 => { email => 'test@example.com', name => 'Test' },
        },
      },
    ]]);
    ok($res->is_success, "Identity/set create");

    # RFC 8621 S6.3: a standard /set, whose only extra create error is
    # forbiddenFrom; a server may also refuse with a standard forbidden.
    my $args    = $res->single_sentence("Identity/set")->arguments;
    my $created = $args->{created}{new1};

    if ($created) {
      jcmp_deeply($created, superhashof({ id => jstr }), "identity created")
        or diag explain $args;

      $tester->request([[
        "Identity/set" => { destroy => [ $created->{id} ] },
      ]]);
    } else {
      jcmp_deeply(
        $args->{notCreated}{new1},
        superhashof({ type => any(qw(forbiddenFrom forbidden)) }),
        "identity refused with forbiddenFrom or forbidden",
      ) or diag explain $args;
    }
  };

  subtest "update name" => sub {
    plan skip_all => "account has no identities" unless defined $id;

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
    # RFC 8620 Section 5.3: the value under updated may be null.
    ok(exists $args->{updated}{$id}, "identity updated") or diag explain $args;

    my $get_res = $tester->request([[
      "Identity/get" => { ids => [$id] },
    ]]);
    my $updated = $get_res->single_sentence("Identity/get")->arguments->{list}[0];
    is($updated->{name}, $new_name, "name was updated");

    $tester->request([[
      "Identity/set" => { update => { $id => { name => $orig_name } } },
    ]]);
  };

  subtest "destroy identity follows mayDelete" => sub {
    plan skip_all => "account has no identities" unless defined $id;

    my $get_res = $tester->request([[
      "Identity/get" => { ids => [$id] },
    ]]);
    my $identity = $get_res->single_sentence("Identity/get")->arguments->{list}[0];

    my $res = $tester->request([[
      "Identity/set" => {
        destroy => [$id],
      },
    ]]);
    ok($res->is_success, "Identity/set destroy");

    my $args = $res->single_sentence("Identity/set")->arguments;
    if ($identity->{mayDelete}) {
      # The server said this one may go; nothing more is promised.
      ok(
        (grep { $_ eq $id } @{ $args->{destroyed} // [] }) || $args->{notDestroyed}{$id},
        "server accounted for the destroy of a deletable identity"
      ) or diag explain $args;
    }
    else {
      # RFC 8621 Section 6: an Identity with mayDelete false is rejected with
      # a standard forbidden SetError.
      ok(!grep({ $_ eq $id } @{ $args->{destroyed} // [] }), "identity not destroyed");
      is($args->{notDestroyed}{$id}{type}, q{forbidden}, "notDestroyed with forbidden")
        or diag explain $args;
    }
  };
};
