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
    "Quota/query" => {},
  ]]);
  ok($res->is_success, "Quota/query") or diag explain $res->response_payload;

  my $args = $res->single_sentence("Quota/query")->arguments;
  ok(defined $args->{queryState},          "has queryState");
  ok(defined $args->{position},            "has position");
  ok(defined $args->{total},               "has total");
  ok(ref $args->{ids} eq 'ARRAY',          "ids is array");
  # RFC 8620 S5.5 lets a server say it cannot calculate changes for these
  # parameters, so only its presence is required.
  ok(defined $args->{canCalculateChanges}, "has canCalculateChanges");

  unless ($args->{total}) {
    pass("server reports no quotas for this account; nothing further to check");
    return;
  }

  subtest "filter by resourceType" => sub {
    my $res = $tester->request([[
      "Quota/query" => { filter => { resourceType => 'octets' } },
    ]]);
    ok($res->is_success, "Quota/query with filter");

    my $args2 = $res->single_sentence("Quota/query")->arguments;
    ok(ref $args2->{ids} eq 'ARRAY', "ids is array");
    if (@{ $args2->{ids} }) {
      my $get_res = $tester->request([[
        "Quota/get" => { ids => $args2->{ids} },
      ]]);
      my $quotas = $get_res->single_sentence("Quota/get")->arguments->{list};
      for my $q (@$quotas) {
        is($q->{resourceType}, 'octets', "quota $q->{id} is octets type");
      }
    }
  };
};
