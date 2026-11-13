use jmaptest;

# RFC 8620 S5.6: "added" holds each id's index in the new results and "MUST be
# sorted in order of index"; splicing out "removed" then splicing in "added"
# must turn the old results into the new ones.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $parent = $account->create_mailbox({ name => "queryChanges parent $^T.$$" });
  $account->create_mailbox({ parentId => $parent->id, name => "qc $_" }) for qw(b d f);

  my %args = (
    filter => { parentId => $parent->id },
    sort   => [ { property => 'name', isAscending => jtrue } ],
  );

  my $query = sub {
    my $res = $tester->request([[ "Mailbox/query" => \%args ]]);
    ok($res->is_success, "Mailbox/query completed")
      or diag explain $res->response_payload;
    return $res->single_sentence("Mailbox/query")->arguments;
  };

  my $old = $query->();
  unless ($old->{canCalculateChanges}) {
    note("canCalculateChanges is false for this query; nothing to test");
    return;
  }
  is(@{ $old->{ids} }, 3, "three mailboxes in the old results");

  $account->create_mailbox({ parentId => $parent->id, name => "qc $_" }) for qw(e a c);

  my $new = $query->();
  is(@{ $new->{ids} }, 6, "six mailboxes in the new results");

  for my $case (
    [ "without upToId", {} ],
    # S5.6: name is mutable, so upToId "is ignored".
    [ "with upToId on a mutable sort", { upToId => $old->{ids}[0] } ],
  ) {
    my ($desc, $extra) = @$case;

    subtest $desc => sub {
      my $res = $tester->request([[
        "Mailbox/queryChanges" => {
          %args, %$extra,
          sinceQueryState => $old->{queryState},
        },
      ]]);
      ok($res->is_success, "Mailbox/queryChanges completed")
        or return diag explain $res->response_payload;

      my $s = $res->single_sentence;
      is($s->name, "Mailbox/queryChanges", "got a Mailbox/queryChanges response")
        or return diag explain $s->arguments;

      my $got = $s->arguments;
      jcmp_deeply(
        $got,
        {
          accountId     => jstr($account->accountId),
          oldQueryState => jstr($old->{queryState}),
          newQueryState => jstr,
          removed       => array_each(jstr),
          added         => array_each({ id => jstr, index => jnum }),
        },
        "response is well formed",
      ) or return diag explain $got;

      my @index = map {; $_->{index} } @{ $got->{added} };
      is_deeply(\@index, [ sort { $a <=> $b } @index ], "added is sorted by index")
        or diag explain $got->{added};

      for my $item (@{ $got->{added} }) {
        is($new->{ids}[ $item->{index} ], $item->{id},
           "added $item->{id} is at index $item->{index} in the new results");
      }

      my %removed = map {; $_ => 1 } @{ $got->{removed} };
      my @ids = grep {; !$removed{$_} } @{ $old->{ids} };
      splice @ids, $_->{index}, 0, $_->{id} for @{ $got->{added} };
      is_deeply(\@ids, $new->{ids}, "the changes turn the old results into the new")
        or diag explain { old => $old->{ids}, new => $new->{ids}, changes => $got };
    };
  }

  # S5.6: three Mailboxes were added, and each added item is one change.
  subtest "more changes than maxChanges" => sub {
    my $res = $tester->request([[
      "Mailbox/queryChanges" => {
        %args,
        sinceQueryState => $old->{queryState},
        maxChanges      => 2,
      },
    ]]);
    ok($res->is_success, "the request completed")
      or return diag explain $res->response_payload;

    my $s = $res->single_sentence;
    is($s->name, "error", "Mailbox/queryChanges is rejected")
      or return diag explain $s->arguments;
    jcmp_deeply(
      $s->arguments,
      superhashof({ type => "tooManyChanges" }),
      "with tooManyChanges",
    ) or diag explain $s->arguments;
  };
};
