use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mailbox = $account->create_mailbox;

  my $state = $account->get_state('mailbox');

  my $res = $tester->request([[
    "Mailbox/changes" => { sinceState => $state, },
  ]]);
  ok($res->is_success, "Mailbox/changes")
    or diag explain $res->http_response->as_string;

  my $changes = $res->single_sentence("Mailbox/changes")->arguments;

  jcmp_deeply(
    $changes,
    superhashof({
      accountId      => jstr($account->accountId),
      oldState       => jstr($state),
      newState       => jstr($state),
      hasMoreChanges => jfalse,
      created        => [],
      updated        => [],
      destroyed      => [],
    }),
    "Response looks good",
  ) or diag explain $res->as_stripped_triples;

  ok(
       ! exists $changes->{updatedProperties}
    || ! defined $changes->{updatedProperties},
    "updatedProperties is null or omitted"
  );
};
