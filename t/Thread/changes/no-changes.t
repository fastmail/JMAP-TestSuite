use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $message = $account->create_mailbox->add_message;

  my $state = $account->get_state('thread');

  my $res = $tester->request([[
    "Thread/changes" => { sinceState => $state, },
  ]]);
  ok($res->is_success, "Thread/changes")
    or diag explain $res->response_payload;

  my $changes = $res->single_sentence("Thread/changes")->arguments;

  jcmp_deeply(
    $changes,
    {
      accountId      => jstr($account->accountId),
      oldState       => jstr($state),
      newState       => jstr,
      hasMoreChanges => jfalse,
      created        => [],
      updated        => [],
      destroyed      => [],
    },
    "Response looks good",
  ) or diag explain $res->as_stripped_triples;

  # RFC 8620 S5.1: servers SHOULD return the same state if nothing changed.
  note("newState differs from oldState though nothing changed (a SHOULD)")
    if ($changes->{newState} // q{}) ne $state;
};
