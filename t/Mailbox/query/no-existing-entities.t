use jmaptest;

# This is about testing when there's no mailboxes, so you need a brand new
# account, basically.
attr pristine => 1;

test {
  my ($self) = @_;

  plan skip_all => "Cyrus requires at least one mailbox"
    if $self->server->isa('JMAP::TestSuite::ServerAdapter::Cyrus');

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  subtest "No arguments" => sub {
    my $res = $tester->request([[
      "Mailbox/query" => {},
    ]]);
    ok($res->is_success, "Mailbox/query")
      or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("Mailbox/query")->arguments,
      superhashof({
        accountId  => jstr($account->accountId),
        queryState => jstr(),
        position   => jnum(0),
        total      => jnum(0),
        ids        => [],
        canCalculateChanges => jbool(),
      }),
      "No mailboxes looks good",
    ) or diag explain $res->as_stripped_triples;
  };
};
