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

  my @email = map {;
    $mailbox->add_message({
      subject    => "keyword change $_ $$",
      receivedAt => "2020-01-01T00:00:0${_}Z",
      keywords   => $_ < 3 ? { jmts_k => jtrue() } : {},
    })
  } 0 .. 3;

  my %args = (
    filter => {
      operator   => 'AND',
      conditions => [ { inMailbox => $mailbox->id }, { hasKeyword => 'jmts_k' } ],
    },
    sort   => [ { property => 'receivedAt', isAscending => jtrue() } ],
  );

  my $query = sub {
    my $res = $tester->request([[ "Email/query" => \%args ]]);
    ok($res->is_success, "Email/query") or diag explain $res->response_payload;
    return $res->single_sentence("Email/query")->arguments;
  };

  my $old = $query->();
  is_deeply(
    [ map {; "$_" } @{ $old->{ids} } ],
    [ map {; $_->id } @email[0 .. 2] ],
    "the three emails with the keyword match",
  ) or diag explain $old;

  unless ($old->{canCalculateChanges}) {
    note("server cannot calculate changes for this query (RFC 8620 S5.5)");
    return;
  }

  my $set = $tester->request([[
    "Email/set" => {
      update => {
        $email[1]->id => { 'keywords/jmts_k' => undef },
        $email[3]->id => { 'keywords/jmts_k' => jtrue() },
      },
    },
  ]]);
  jcmp_deeply(
    [ sort keys %{ $set->single_sentence("Email/set")->arguments->{updated} || {} } ],
    [ sort map {; $_->id } @email[1, 3] ],
    "moved the keyword from one email to another",
  ) or diag explain $set->as_stripped_triples;

  my $new = $query->();

  my $res = $tester->request([[
    "Email/queryChanges" => { %args, sinceQueryState => $old->{queryState} },
  ]]);
  ok($res->is_success, "Email/queryChanges")
    or diag explain $res->response_payload;

  my $changes = $res->sentence(0)->as_stripped_pair;
  is($changes->[0], 'Email/queryChanges', 'got Email/queryChanges')
    or return diag explain $changes;
  $changes = $changes->[1];

  my %removed = map {; $_ => 1 } @{ $changes->{removed} || [] };
  my %added   = map {; $_->{id} => $_->{index} } @{ $changes->{added} || [] };

  # RFC 8620 S5.6: with a mutable property in the filter, removed MUST hold
  # every current result whose property may have changed, and added
  # reinserts each of them.
  ok($removed{ $email[1]->id }, "the email that lost the keyword is removed");
  ok(! exists $added{ $email[1]->id }, "and is not added back");
  ok($removed{ $email[3]->id }, "the email that gained the keyword is in removed");
  is($added{ $email[3]->id }, 2, "and is added at its new index");

  # RFC 8620 S5.6: splicing out removed and splicing in added, lowest index
  # first, turns the old results into the new ones.
  my @ids = grep {; ! $removed{$_} } map {; "$_" } @{ $old->{ids} };
  for my $item (sort { $a->{index} <=> $b->{index} } @{ $changes->{added} || [] }) {
    splice @ids, $item->{index}, 0, "$item->{id}";
  }
  is_deeply(\@ids, [ map {; "$_" } @{ $new->{ids} } ], "the changes turn the old results into the new")
    or diag explain [ $old, $changes, $new ];
};
