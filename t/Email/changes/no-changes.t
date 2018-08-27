use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $message = $account->create_mailbox->add_message;

  my $state = $account->get_state('email');

  my $res = $tester->request([[
    "Email/changes" => { sinceState => $state, },
  ]]);
  ok($res->is_success, "Email/changes")
    or diag explain $res->http_response->as_string;

  my $changes = $res->single_sentence("Email/changes")->arguments;

  jcmp_deeply(
    $changes,
    {
      accountId      => jstr($account->accountId),
      oldState       => jstr($state),
      newState       => jstr($state),
      hasMoreChanges => jfalse,
      created        => [],
      updated        => [],
      destroyed      => [],
    },
    "Response looks good",
  ) or diag explain $res->as_stripped_triples;
};
