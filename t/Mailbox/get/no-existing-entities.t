use jmaptest;

# Can't have existing data so must be pristine
attr pristine => 1;

test {
  my ($self) = @_;

  plan skip_all => "Cyrus requires at least one mailbox"
    if $self->server->isa('JMAP::TestSuite::ServerAdapter::Cyrus');

  my $account = $self->any_account;
  my $tester  = $account->tester;

  subtest "No arguments" => sub {
    my $res = $tester->request([[
      "Mailbox/get" => {},
    ]]);
    ok($res->is_success, "Mailbox/get")
      or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("Mailbox/get")->arguments,
      superhashof({
        accountId => jstr($account->accountId),
        state     => jstr(),
        list      => [],
        notFound  => [],
      }),
      "No mailboxes looks good",
    );
  };
};
