use jmaptest;

# Can't have existing data so must be pristine
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

    # Nothing in RFC 8621 says what a new account contains: servers provision
    # INBOX and often the role mailboxes. Only well-formedness is checked.
    note(scalar(@{ $args->{list} }) . " server-provisioned mailbox(es) in a fresh account");
  };
};
