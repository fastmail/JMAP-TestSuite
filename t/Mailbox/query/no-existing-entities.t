use jmaptest;

# This is about testing when there's no mailboxes, so you need a brand new
# account, basically.
attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  subtest "No arguments" => sub {
    my $res = $tester->request([[
      "Mailbox/query" => {},
    ]]);
    ok($res->is_success, "Mailbox/query")
      or diag explain $res->response_payload;

    my $args = $res->single_sentence("Mailbox/query")->arguments;

    jcmp_deeply(
      $args,
      superhashof({
        accountId  => jstr($account->accountId),
        queryState => jstr(),
        position   => jnum(0),
        canCalculateChanges => jbool(),
      }),
      "Mailbox/query response looks good",
    ) or diag explain $res->as_stripped_triples;

    # Nothing in RFC 8621 says what a new account contains: servers provision
    # INBOX and often the role mailboxes. Only well-formedness is checked.
    note(scalar(@{ $args->{ids} }) . " server-provisioned mailbox(es) in a fresh account");
  };
};
