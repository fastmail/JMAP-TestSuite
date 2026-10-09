use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mailbox = $account->create_mailbox;

  my $state = $account->get_state('mailbox');

  my $res = $tester->request([[
    "Mailbox/changes" => { sinceState => $state, },
  ]]);
  ok($res->is_success, "Mailbox/changes")
    or diag explain $res->response_payload;

  my $changes = $res->single_sentence("Mailbox/changes")->arguments;

  jcmp_deeply(
    $changes,
    superhashof({
      accountId      => jstr($account->accountId),
      oldState       => jstr($state),
      newState       => jstr,
      hasMoreChanges => jfalse,
      created        => [],
      updated        => [],
      destroyed      => [],
    }),
    "Response looks good",
  ) or diag explain $res->as_stripped_triples;

  # RFC 8620 S5.1: servers SHOULD return the same state if nothing changed.
  note("newState differs from oldState though nothing changed (a SHOULD)")
    if ($changes->{newState} // q{}) ne $state;

  ok(
       ! exists $changes->{updatedProperties}
    || ! defined $changes->{updatedProperties},
    "updatedProperties is null or omitted"
  );
};
