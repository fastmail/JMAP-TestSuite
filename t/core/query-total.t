use jmaptest;

# RFC 8620 S5.5 and S5.6: "total" is returned only if requested, and "MUST be
# omitted if the calculateTotal request argument is not true".

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $parent = $account->create_mailbox({ name => "total parent $^T.$$" });
  $account->create_mailbox({ parentId => $parent->id, name => "total $_" })
    for qw(a b c);

  my %base = (
    filter => { parentId => $parent->id },
    sort   => [ { property => 'name', isAscending => jtrue } ],
  );

  my $query_state;
  my $can_calculate;

  for my $case (
    [ "calculateTotal omitted", {} ],
    [ "calculateTotal false",   { calculateTotal => jfalse } ],
    [ "calculateTotal true",    { calculateTotal => jtrue } ],
  ) {
    my ($desc, $args) = @$case;

    subtest "Mailbox/query, $desc" => sub {
      my $res = $tester->request([[ "Mailbox/query" => { %base, %$args } ]]);
      ok($res->is_success, "Mailbox/query completed")
        or return diag explain $res->response_payload;

      my $got = $res->single_sentence("Mailbox/query")->arguments;
      $query_state   //= $got->{queryState};
      $can_calculate //= $got->{canCalculateChanges};

      if ($args->{calculateTotal}) {
        jcmp_deeply($got->{total}, jnum(3), "total is the number of results")
          or diag explain $got;
      } else {
        ok(!exists $got->{total}, "no total") or diag explain $got;
      }
    };
  }

  unless ($can_calculate) {
    note("canCalculateChanges is false for this query; skipping /queryChanges");
    return;
  }

  for my $case (
    [ "calculateTotal omitted", {} ],
    [ "calculateTotal false",   { calculateTotal => jfalse } ],
    [ "calculateTotal true",    { calculateTotal => jtrue } ],
  ) {
    my ($desc, $args) = @$case;

    subtest "Mailbox/queryChanges, $desc" => sub {
      my $res = $tester->request([[
        "Mailbox/queryChanges" => { %base, %$args, sinceQueryState => $query_state },
      ]]);
      ok($res->is_success, "Mailbox/queryChanges completed")
        or return diag explain $res->response_payload;

      my $got = $res->single_sentence("Mailbox/queryChanges")->arguments;

      if ($args->{calculateTotal}) {
        jcmp_deeply($got->{total}, jnum(3), "total is the number of results")
          or diag explain $got;
      } else {
        ok(!exists $got->{total}, "no total") or diag explain $got;
      }
    };
  }
};
