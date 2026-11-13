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

  my $first = $mailbox->add_message({
    subject    => "collapse changes $$",
    receivedAt => '2020-01-01T00:00:01Z',
  });
  my $single = $mailbox->add_message({
    subject    => "alone $$",
    receivedAt => '2020-01-01T00:00:02Z',
  });

  my %args = (
    filter          => { inMailbox => $mailbox->id },
    sort            => [ { property => 'receivedAt', isAscending => jfalse() } ],
    collapseThreads => jtrue(),
  );

  my $query = sub {
    my $res = $tester->request([[ "Email/query" => \%args ]]);
    ok($res->is_success, "Email/query") or diag explain $res->response_payload;
    return $res->single_sentence("Email/query")->arguments;
  };

  my $old = $query->();

  unless ($old->{canCalculateChanges}) {
    note("server cannot calculate changes for this query (RFC 8620 S5.5)");
    return;
  }

  my $reply = $first->reply({
    subject    => "Re: collapse changes $$",
    receivedAt => '2020-01-01T00:00:03Z',
  });

  # RFC 8621 S3: the threading algorithm is not mandated.
  unless ($reply->threadId eq $first->threadId) {
    note("server did not thread the reply with its parent; nothing to collapse");
    return;
  }

  my $new = $query->();
  is_deeply(
    [ map {; "$_" } @{ $new->{ids} } ],
    [ $reply->id, $single->id ],
    "the newer reply now stands for the thread",
  ) or return diag explain $new;

  # RFC 8621 S4.5: queryChanges takes "The "collapseThreads" argument that
  # was used with "Email/query"".
  my $res = $tester->request([[
    "Email/queryChanges" => { %args, sinceQueryState => $old->{queryState} },
  ]]);
  ok($res->is_success, "Email/queryChanges")
    or return diag explain $res->response_payload;

  my ($name, $changes) = @{ $res->sentence(0)->as_stripped_pair };
  is($name, 'Email/queryChanges', 'got Email/queryChanges')
    or return diag explain $changes;

  my %removed = map {; $_ => 1 } @{ $changes->{removed} || [] };
  ok($removed{ $first->id }, "the email the reply replaced is removed");

  # RFC 8620 S5.6: splicing out removed and splicing in added, lowest index
  # first, turns the old results into the new ones.
  my @ids = grep {; ! $removed{$_} } map {; "$_" } @{ $old->{ids} };
  for my $item (sort { $a->{index} <=> $b->{index} } @{ $changes->{added} || [] }) {
    splice @ids, $item->{index}, 0, "$item->{id}";
  }
  is_deeply(\@ids, [ map {; "$_" } @{ $new->{ids} } ], "the changes turn the old results into the new")
    or diag explain [ $old, $changes, $new ];
};
