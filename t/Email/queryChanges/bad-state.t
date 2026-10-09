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
  $mailbox->add_message;

  my %args = (
    filter => { inMailbox => $mailbox->id },
    sort   => [ { property => 'receivedAt', isAscending => jtrue() } ],
  );

  my $query = $tester->request([[ "Email/query" => \%args ]]);
  ok($query->is_success, "Email/query") or diag explain $query->response_payload;

  unless ($query->single_sentence("Email/query")->arguments->{canCalculateChanges}) {
    note("server cannot calculate changes for this query (RFC 8620 S5.5)");
    return;
  }

  # RFC 8620 S5.6: "cannotCalculateChanges": "The server cannot calculate
  # the changes from the queryState string given by the client".
  my $res = $tester->request([[
    "Email/queryChanges" => {
      %args,
      sinceQueryState => 'jmts-no-such-state-' . time . '-' . $$,
    },
  ]]);
  ok($res->is_success, "Email/queryChanges")
    or return diag explain $res->response_payload;

  jcmp_deeply(
    $res->sentence(0)->as_stripped_pair,
    [ error => superhashof({ type => 'cannotCalculateChanges' }) ],
    "an unknown queryState is cannotCalculateChanges",
  ) or diag explain $res->as_stripped_triples;
};
