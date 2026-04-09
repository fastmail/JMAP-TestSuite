use jmaptest;

# This is about testing when there's no mailboxes, so you need a brand new
# account, basically.
attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

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

    # Filter out INBOX from results — most servers auto-create it
    my @ids = @{ $args->{ids} };
    if (@ids) {
      my $get_res = $tester->request([[
        "Mailbox/get" => { ids => \@ids },
      ]]);
      my @non_inbox = grep { ($_->{role} // '') ne 'inbox' }
        @{ $get_res->single_sentence("Mailbox/get")->arguments->{list} };
      is(@non_inbox, 0, "No non-INBOX mailboxes exist");
    } else {
      pass("No mailboxes at all");
    }
  };
};
