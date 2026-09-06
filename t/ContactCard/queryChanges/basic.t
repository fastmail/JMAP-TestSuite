use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:contacts',
  );

  my $ab = $account->create_address_book;

  my $card1 = $account->create_contact_card({
    name           => { full => 'QC Seed Contact' },
    addressBookIds => { $ab->id => \1 },
  });

  my %args = (
    filter => { inAddressBook => $ab->id },
    sort   => [{ property => 'name', isAscending => jtrue() }],
  );

  my $res = $tester->request([[
    "ContactCard/query" => \%args,
  ]]);
  ok($res->is_success, "ContactCard/query baseline") or diag explain $res->response_payload;

  my $base = $res->single_sentence("ContactCard/query")->arguments;
  my $query_state = $base->{queryState};
  ok(defined $query_state, "got queryState");
  # RFC 8620 S5.5 lets a server answer canCalculateChanges false for a given
  # filter/sort; nothing to test then.
  ok(defined $base->{canCalculateChanges}, "has canCalculateChanges");
  unless ($base->{canCalculateChanges}) {
    note("server does not support ContactCard/queryChanges for this "
       . "filter/sort, so the rest of this file does not apply");
    return;
  }

  subtest "no changes" => sub {
    my $res = $tester->request([[
      "ContactCard/queryChanges" => {
        %args,
        sinceQueryState => $query_state,
      },
    ]]);
    ok($res->is_success, "ContactCard/queryChanges") or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("ContactCard/queryChanges")->arguments,
      superhashof({
        oldQueryState => jstr($query_state),
        newQueryState => jstr($query_state),
        added         => [],
        removed       => [],
      }),
      "no-changes response",
    ) or diag explain $res->as_stripped_triples;
  };

  my $card2 = $account->create_contact_card({
    name           => { full => 'QC Added Contact' },
    addressBookIds => { $ab->id => \1 },
  });

  subtest "created card appears in added" => sub {
    my $res = $tester->request([[
      "ContactCard/queryChanges" => {
        %args,
        sinceQueryState => $query_state,
      },
    ]]);
    ok($res->is_success, "ContactCard/queryChanges") or diag explain $res->response_payload;

    my $args_out = $res->single_sentence("ContactCard/queryChanges")->arguments;
    jcmp_deeply(
      $args_out,
      superhashof({
        oldQueryState => jstr($query_state),
        newQueryState => none(jstr($query_state)),
        added         => supersetof(superhashof({ id => jstr($card2->id) })),
        removed       => ignore,
      }),
      "new card in added",
    ) or diag explain $res->as_stripped_triples;

    $query_state = $args_out->{newQueryState};
  };

  $tester->request_ok(
    [ "ContactCard/set" => { destroy => [ $card1->id ] } ],
    superhashof({ destroyed => [ $card1->id ] }),
    "destroyed card",
  );

  subtest "destroyed card appears in removed" => sub {
    my $res = $tester->request([[
      "ContactCard/queryChanges" => {
        %args,
        sinceQueryState => $query_state,
      },
    ]]);
    ok($res->is_success, "ContactCard/queryChanges") or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("ContactCard/queryChanges")->arguments,
      superhashof({
        oldQueryState => jstr($query_state),
        newQueryState => none(jstr($query_state)),
        removed       => supersetof($card1->id),
        added         => ignore,
      }),
      "destroyed card in removed",
    ) or diag explain $res->as_stripped_triples;
  };
};
