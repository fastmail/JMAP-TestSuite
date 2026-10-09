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
  $mailbox->add_message({ receivedAt => '2020-01-01T00:00:00Z' });

  my %args = (
    filter => { inMailbox => $mailbox->id },
    sort   => [ { property => 'receivedAt', isAscending => jtrue() } ],
  );

  my $query = $tester->request([[ "Email/query" => \%args ]]);
  ok($query->is_success, "Email/query") or diag explain $query->response_payload;
  my $old = $query->single_sentence("Email/query")->arguments;

  unless ($old->{canCalculateChanges}) {
    note("server cannot calculate changes for this query (RFC 8620 S5.5)");
    return;
  }

  $mailbox->add_message({ receivedAt => "2020-01-01T00:00:0${_}Z" }) for 1 .. 3;

  # RFC 8620 S5.6: "tooManyChanges": "There are more changes than the
  # client's "maxChanges" argument.  Each item in the removed or added array
  # is considered to be one change."
  my $res = $tester->request([[
    "Email/queryChanges" => {
      %args,
      sinceQueryState => $old->{queryState},
      maxChanges      => 2,
    },
  ]]);
  ok($res->is_success, "Email/queryChanges")
    or return diag explain $res->response_payload;

  jcmp_deeply(
    $res->sentence(0)->as_stripped_pair,
    [ error => superhashof({ type => 'tooManyChanges' }) ],
    "three additions with maxChanges 2 is tooManyChanges",
  ) or diag explain $res->as_stripped_triples;
};
