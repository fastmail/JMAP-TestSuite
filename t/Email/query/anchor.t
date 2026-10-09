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
      subject    => "anchor $_ $$",
      receivedAt => "2020-01-01T00:00:0${_}Z",
    })
  } 0 .. 4;

  my $other = $account->create_mailbox->add_message({ subject => "elsewhere $$" });

  my %base = (
    filter => { inMailbox => $mailbox->id },
    sort   => [ { property => 'receivedAt', isAscending => jtrue() } ],
  );

  # RFC 8620 S5.5: the anchor's index plus anchorOffset, clamped to 0, is
  # used "exactly as though it were supplied as the "position" argument",
  # and any position the client sends "MUST be ignored".
  for my $test (
    [ 'anchor alone',           { anchor => $email[2]->id },                                2, [ 2 .. 4 ] ],
    [ 'anchorOffset -1',        { anchor => $email[2]->id, anchorOffset => -1, limit => 2 }, 1, [ 1, 2 ] ],
    [ 'anchorOffset 1',         { anchor => $email[2]->id, anchorOffset =>  1 },            3, [ 3, 4 ] ],
    [ 'anchorOffset clamped',   { anchor => $email[1]->id, anchorOffset => -5, limit => 2 }, 0, [ 0, 1 ] ],
    [ 'position is ignored',    { anchor => $email[3]->id, position => 0 },                 3, [ 3, 4 ] ],
    [ 'anchorOffset no anchor', { anchorOffset => 2, limit => 1 },                          0, [ 0 ] ],
  ) {
    my ($desc, $args, $position, $want) = @$test;

    my $res = $tester->request([[ "Email/query" => { %base, %$args } ]]);
    ok($res->is_success, "Email/query $desc")
      or diag explain $res->response_payload;

    jcmp_deeply(
      $res->sentence(0)->as_stripped_pair,
      [ 'Email/query' => superhashof({
        position => $position,
        ids      => [ map {; $email[$_]->id } @$want ],
      }) ],
      "$desc gives position $position and ids [@$want]",
    ) or diag explain $res->as_stripped_triples;
  }

  # RFC 8620 S5.5: "If the anchor is not found, the call is rejected with an
  # "anchorNotFound" error."
  my $res = $tester->request([[
    "Email/query" => { %base, anchor => $other->id },
  ]]);
  ok($res->is_success, "Email/query with an anchor outside the results")
    or diag explain $res->response_payload;

  jcmp_deeply(
    $res->sentence(0)->as_stripped_pair,
    [ error => superhashof({ type => 'anchorNotFound' }) ],
    "anchorNotFound",
  ) or diag explain $res->as_stripped_triples;
};
