use jmaptest;

# RFC 8620 S5.5: an anchor's index plus anchorOffset, clamped to 0, is used
# as the position; any position given with an anchor "MUST be ignored"; an
# anchor not in the results is anchorNotFound.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $parent = $account->create_mailbox({ name => "anchor parent $^T.$$" });
  my @kids   = map {;
    $account->create_mailbox({ parentId => $parent->id, name => "anchor $_" })
  } qw(a b c d);
  my @ids = map {; $_->id } @kids;

  my %base = (
    filter => { parentId => $parent->id },
    sort   => [ { property => 'name', isAscending => jtrue } ],
  );

  my $query = sub {
    my ($args) = @_;
    my $res = $tester->request([[ "Mailbox/query" => { %base, %$args } ]]);
    ok($res->is_success, "Mailbox/query completed")
      or diag explain $res->response_payload;
    return $res->single_sentence;
  };

  my $want = sub {
    my ($got, $position, @want_ids) = @_;
    return {
      accountId           => jstr($account->accountId),
      queryState          => jstr,
      canCalculateChanges => jbool,
      position            => jnum($position),
      ids                 => [ map {; jstr($_) } @want_ids ],
      (exists $got->{limit} ? (limit => jnum) : ()),
    };
  };

  for my $case (
    [ "anchor alone",           { anchor => $ids[2] },                         2, @ids[2,3] ],
    [ "negative anchorOffset",  { anchor => $ids[2], anchorOffset => -1 },     1, @ids[1..3] ],
    [ "positive anchorOffset",  { anchor => $ids[1], anchorOffset => 2 },      3, $ids[3] ],
    [ "offset clamped to 0",    { anchor => $ids[1], anchorOffset => -10 },    0, @ids ],
    [ "offset with limit",      { anchor => $ids[1], anchorOffset => -1, limit => 2 }, 0, @ids[0,1] ],
    [ "position is ignored",    { anchor => $ids[1], position => 3 },          1, @ids[1..3] ],
    [ "negative position is ignored", { anchor => $ids[3], position => -4 },   3, $ids[3] ],
  ) {
    my ($desc, $args, $position, @want_ids) = @$case;

    subtest $desc => sub {
      my $s = $query->($args);
      is($s->name, "Mailbox/query", "got a Mailbox/query response")
        or return diag explain $s->arguments;
      jcmp_deeply(
        $s->arguments,
        $want->($s->arguments, $position, @want_ids),
        "window starts at index $position",
      ) or diag explain $s->arguments;
    };
  }

  subtest "anchor not in the results" => sub {
    my $s = $query->({ anchor => $parent->id, position => 0 });
    is($s->name, "error", "Mailbox/query is rejected")
      or return diag explain $s->arguments;
    jcmp_deeply(
      $s->arguments,
      superhashof({ type => "anchorNotFound" }),
      "with anchorNotFound",
    ) or diag explain $s->arguments;
  };
};
