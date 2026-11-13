use jmaptest;

# RFC 8620 S5.5: a negative position "MUST be added to the total number of
# results", and "if still negative, it's clamped to 0".

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $parent = $account->create_mailbox({ name => "position parent $^T.$$" });
  my @ids    = map {;
    $account->create_mailbox({ parentId => $parent->id, name => "position $_" })->id
  } qw(a b c d);

  for my $case (
    [ "position -1",  -1,  3, $ids[3] ],
    [ "position -3",  -3,  1, @ids[1..3] ],
    [ "position -4",  -4,  0, @ids ],
    [ "position -10", -10, 0, @ids ],
  ) {
    my ($desc, $position, $want_position, @want_ids) = @$case;

    subtest $desc => sub {
      my $res = $tester->request([[
        "Mailbox/query" => {
          filter   => { parentId => $parent->id },
          sort     => [ { property => 'name', isAscending => jtrue } ],
          position => $position,
        },
      ]]);
      ok($res->is_success, "Mailbox/query completed")
        or return diag explain $res->response_payload;

      my $s = $res->single_sentence;
      is($s->name, "Mailbox/query", "got a Mailbox/query response")
        or return diag explain $s->arguments;

      my $got = $s->arguments;
      jcmp_deeply(
        $got,
        {
          accountId           => jstr($account->accountId),
          queryState          => jstr,
          canCalculateChanges => jbool,
          position            => jnum($want_position),
          ids                 => [ map {; jstr($_) } @want_ids ],
          (exists $got->{limit} ? (limit => jnum) : ()),
        },
        "window starts at index $want_position",
      ) or diag explain $got;
    };
  }
};
