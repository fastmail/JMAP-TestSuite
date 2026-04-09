use jmaptest;

# Can't have existing data so must be pristine
attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  subtest "No arguments" => sub {
    my $res = $tester->request([[
      "Mailbox/get" => {},
    ]]);
    ok($res->is_success, "Mailbox/get")
      or diag explain $res->response_payload;

    my $args = $res->single_sentence("Mailbox/get")->arguments;

    jcmp_deeply(
      $args,
      superhashof({
        accountId => jstr($account->accountId),
        state     => jstr(),
        notFound  => [],
      }),
      "Mailbox/get response looks good",
    );

    # Filter out INBOX — most servers auto-create it
    my @non_inbox = grep { ($_->{role} // '') ne 'inbox' } @{ $args->{list} };
    is(@non_inbox, 0, "No non-INBOX mailboxes exist");
  };
};
