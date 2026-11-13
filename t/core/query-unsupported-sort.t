use jmaptest;

# RFC 8620 S5.5: a "sort" that "is syntactically valid, but it includes a
# property the server does not support sorting on" is unsupportedSort.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  for my $sort (
    [ { property => "jmtsNoSuchProperty" } ],
    [ { property => "name" }, { property => "jmtsNoSuchProperty", isAscending => jfalse } ],
  ) {
    my $desc = join q{, }, map {; $_->{property} } @$sort;

    subtest "sort by $desc" => sub {
      my $res = $tester->request([[ "Mailbox/query" => { sort => $sort } ]]);
      ok($res->is_success, "the request completed")
        or return diag explain $res->response_payload;

      my $s = $res->single_sentence;
      is($s->name, "error", "Mailbox/query is rejected")
        or return diag explain $res->as_stripped_triples;
      jcmp_deeply(
        $s->arguments,
        superhashof({ type => "unsupportedSort" }),
        "with unsupportedSort",
      ) or diag explain $res->as_stripped_triples;
    };
  }
};
