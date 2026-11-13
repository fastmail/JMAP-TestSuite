use jmaptest;

# RFC 8620 S5.5: a filter the server "cannot process" is unsupportedFilter. A
# condition property the type does not define may instead fail the argument's
# type, so invalidArguments is accepted too; a result list is not.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  for my $case (
    [ "an unknown condition", { jmtsNoSuchProperty => "x" } ],
    [ "an unknown condition inside an operator", {
        operator   => "AND",
        conditions => [ { name => "x" }, { jmtsNoSuchProperty => "x" } ],
      } ],
  ) {
    my ($desc, $filter) = @$case;

    subtest $desc => sub {
      my $res = $tester->request([[ "Mailbox/query" => { filter => $filter } ]]);
      ok($res->is_success, "the request completed")
        or return diag explain $res->response_payload;

      my $s = $res->single_sentence;
      is($s->name, "error", "Mailbox/query is rejected")
        or return diag explain $res->as_stripped_triples;
      jcmp_deeply(
        $s->arguments,
        superhashof({ type => any(qw(unsupportedFilter invalidArguments)) }),
        "with unsupportedFilter or invalidArguments",
      ) or diag explain $res->as_stripped_triples;
    };
  }
};
