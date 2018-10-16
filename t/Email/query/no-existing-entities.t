use jmaptest;
# Can't have existing entries so must be pristine
attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  subtest "No arguments" => sub {
    my $res = $tester->request([[
      "Email/query" => {},
    ]]);
    ok($res->is_success, "Email/query")
      or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("Email/query")->arguments,
      superhashof({
        accountId  => jstr($account->accountId),
        queryState => jstr(),
        position   => jnum(0),
        total      => jnum(0),
        ids        => [],
        canCalculateChanges => jbool(),
      }),
      "No Emailes looks good",
    ) or diag explain $res->as_stripped_triples;
  };
};
