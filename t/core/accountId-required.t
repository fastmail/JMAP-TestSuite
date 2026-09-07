use jmaptest;

# RFC 8620 S3.6.2: every standard method except Core/echo requires accountId,
# so omitting it is invalidArguments and naming an unknown account is
# accountNotFound.  The harness injects accountId on every call; passing
# accountId => \undef suppresses it.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my @methods = (
    [ 'Mailbox/get'   => {} ],
    [ 'Mailbox/query' => {} ],
    [ 'Email/get'     => { ids => [] } ],
    [ 'Email/query'   => {} ],
    [ 'Thread/get'    => { ids => [] } ],
  );

  subtest "missing accountId -> invalidArguments" => sub {
    for my $m (@methods) {
      my ($name, $args) = @$m;
      my $res = $tester->request([[
        $name => { %$args, accountId => \undef },
      ]]);
      ok($res->is_success, "$name request completed")
        or diag explain $res->response_payload;

      my $s = $res->sentence(0);
      is($s->name, 'error', "$name without accountId is an error")
        or diag explain $res->as_stripped_triples;
      jcmp_deeply(
        $s->arguments,
        superhashof({ type => 'invalidArguments' }),
        "$name without accountId -> invalidArguments",
      ) or diag explain $res->as_stripped_triples;
    }
  };

  subtest "unknown accountId -> accountNotFound" => sub {
    my $bogus = "no-such-account-" . join '', map { ('a'..'z')[rand 26] } 1..12;
    for my $m (@methods) {
      my ($name, $args) = @$m;
      my $res = $tester->request([[
        $name => { %$args, accountId => $bogus },
      ]]);
      ok($res->is_success, "$name request completed")
        or diag explain $res->response_payload;

      my $s = $res->sentence(0);
      is($s->name, 'error', "$name with unknown accountId is an error")
        or diag explain $res->as_stripped_triples;
      jcmp_deeply(
        $s->arguments,
        superhashof({ type => 'accountNotFound' }),
        "$name with unknown accountId -> accountNotFound",
      ) or diag explain $res->as_stripped_triples;
    }
  };

  subtest "Core/echo needs no accountId" => sub {
    my $res = $tester->request([[
      'Core/echo' => { hello => 'world', accountId => \undef },
    ]]);
    ok($res->is_success, "Core/echo request completed")
      or diag explain $res->response_payload;
    my $s = $res->sentence(0);
    is($s->name, 'Core/echo', "Core/echo without accountId succeeds")
      or diag explain $res->as_stripped_triples;
    jcmp_deeply($s->arguments, { hello => 'world' }, "echoed arguments exactly")
      or diag explain $res->as_stripped_triples;
  };
};
