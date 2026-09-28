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

  my $create_res = $tester->request([[
    "ContactCard/set" => {
      create => {
        c1 => {
          q(@type)       => 'Card',
          version        => '1.0',
          addressBookIds => { $ab->id => \1 },
          name           => { full => 'Alice Original' },
          emails         => {
            e1 => { contexts => { work => \1 }, address => 'alice@example.com' },
          },
          # Seeded so the phones/{id} patch below is legal: RFC 8620 S5.3
          # requires a patch pointer's parent to already exist.
          phones         => {
            p0 => { contexts => { private => \1 }, number => '+1-555-0000' },
          },
        },
      },
    },
  ]]);
  ok($create_res->is_success, "ContactCard/set create")
    or diag explain $create_res->response_payload;

  my $id = $create_res->single_sentence("ContactCard/set")->arguments->{created}{c1}{id};
  ok($id, 'got contact id');

  subtest "Patch name/full (pointer into object)" => sub {
    my $res = $tester->request([[
      "ContactCard/set" => {
        update => { $id => { 'name/full' => 'Alice Patched' } },
      },
    ]]);
    ok($res->is_success, "patch name/full");
    my $args = $res->single_sentence("ContactCard/set")->arguments;
    jcmp_deeply(
      $args,
      superhashof({
        accountId => jstr($account->accountId),
        oldState  => jstr(),
        newState  => jstr(),
        updated   => superhashof({ $id => ignore() }),
      }),
      "update response looks good",
    ) or diag explain $res->as_stripped_triples;
    ok(!$args->{notUpdated}{$id}, 'card not in notUpdated');

    my $got = $tester->request([[
      "ContactCard/get" => { ids => [$id], properties => ['name'] },
    ]])->single_sentence("ContactCard/get")->arguments->{list}[0];
    is($got->{name}{full}, 'Alice Patched', 'name/full round-trips');
  };

  subtest "Patch emails/{id} — add a new email entry" => sub {
    my $res = $tester->request([[
      "ContactCard/set" => {
        update => {
          $id => {
            'emails/home1' => {
              contexts => { private => \1 },
              address  => 'alice.home@example.com',
            },
          },
        },
      },
    ]]);
    ok($res->is_success, "patch emails/home1");
    my $args = $res->single_sentence("ContactCard/set")->arguments;
    ok(exists $args->{updated}{$id}, 'card updated') or diag explain $args->{notUpdated};

    my $got = $tester->request([[
      "ContactCard/get" => { ids => [$id], properties => ['emails'] },
    ]])->single_sentence("ContactCard/get")->arguments->{list}[0];
    my $emails = $got->{emails} // {};
    my ($home) = grep { ($_->{address} // '') eq 'alice.home@example.com' }
                 values %{ ref($emails) eq 'HASH' ? $emails : {} };
    ok($home, 'home email address found');
  };

  subtest "Patch phones/{id} — add a phone entry" => sub {
    my $res = $tester->request([[
      "ContactCard/set" => {
        update => {
          $id => {
            'phones/p1' => {
              contexts => { work => \1 },
              number   => '+1-555-0100',
            },
          },
        },
      },
    ]]);
    ok($res->is_success, "patch phones/p1");
    my $args = $res->single_sentence("ContactCard/set")->arguments;
    ok(exists $args->{updated}{$id}, 'card updated')
      or diag explain $args->{notUpdated};

    my $got = $tester->request([[
      "ContactCard/get" => { ids => [$id], properties => ['phones'] },
    ]])->single_sentence("ContactCard/get")->arguments->{list}[0];
    my $phones = $got->{phones} // {};
    my ($phone) = grep { ($_->{number} // '') eq '+1-555-0100' }
                  values %{ ref($phones) eq 'HASH' ? $phones : {} };
    ok($phone, 'phone number found');
  };

  subtest "Replace entire name object" => sub {
    my $res = $tester->request([[
      "ContactCard/set" => {
        update => {
          $id => {
            name => {
              full       => 'Alice B. Cooper',
              components => [
                { kind => 'given',   value => 'Alice' },
                { kind => 'given2',  value => 'B.' },
                { kind => 'surname', value => 'Cooper' },
              ],
            },
          },
        },
      },
    ]]);
    ok($res->is_success, "replace name object");
    my $args = $res->single_sentence("ContactCard/set")->arguments;
    ok(exists $args->{updated}{$id}, 'card updated') or diag explain $args->{notUpdated};

    my $got = $tester->request([[
      "ContactCard/get" => { ids => [$id], properties => ['name'] },
    ]])->single_sentence("ContactCard/get")->arguments->{list}[0];
    is($got->{name}{full}, 'Alice B. Cooper', 'name/full round-trips after full replace');
    ok($got->{name}{components}, 'components present');
  };

  subtest "Replace entire emails map" => sub {
    my $res = $tester->request([[
      "ContactCard/set" => {
        update => {
          $id => {
            emails => {
              only1 => {
                contexts => { work => \1 },
                address  => 'alice.new@example.com',
              },
            },
          },
        },
      },
    ]]);
    ok($res->is_success, "replace emails map");
    my $args = $res->single_sentence("ContactCard/set")->arguments;
    ok(exists $args->{updated}{$id}, 'card updated') or diag explain $args->{notUpdated};

    my $got = $tester->request([[
      "ContactCard/get" => { ids => [$id], properties => ['emails'] },
    ]])->single_sentence("ContactCard/get")->arguments->{list}[0];
    my $emails = $got->{emails} // {};
    my @addresses = map { $_->{address} } values %{ ref($emails) eq 'HASH' ? $emails : {} };
    ok((grep { $_ eq 'alice.new@example.com' } @addresses) ? 1 : 0, 'new address present');
    ok((grep { $_ eq 'alice@example.com' } @addresses) ? 0 : 1,
       'old address gone after full emails replace');
  };

  subtest "Replace notes (whole property)" => sub {
    my $res = $tester->request([[
      "ContactCard/set" => {
        update => {
          $id => {
            notes => {
              n1 => { note => 'Met at conference 2024.' },
            },
          },
        },
      },
    ]]);
    ok($res->is_success, "set notes");
    my $args = $res->single_sentence("ContactCard/set")->arguments;
    ok(exists $args->{updated}{$id}, 'card updated') or diag explain $args->{notUpdated};

    my $got = $tester->request([[
      "ContactCard/get" => { ids => [$id], properties => ['notes'] },
    ]])->single_sentence("ContactCard/get")->arguments->{list}[0];
    my $notes = $got->{notes} // {};
    my ($note) = grep { ($_->{note} // '') eq 'Met at conference 2024.' }
                 values %{ ref($notes) eq 'HASH' ? $notes : {} };
    ok($note, 'note text round-trips');
  };

  subtest "Update notFound returns error" => sub {
    my $res = $tester->request([[
      "ContactCard/set" => {
        update => { 'nosuchcard' => { 'name/full' => 'Ghost' } },
      },
    ]]);
    ok($res->is_success, "request succeeds");
    my $args = $res->single_sentence("ContactCard/set")->arguments;
    ok($args->{notUpdated}{nosuchcard}, 'unknown id in notUpdated');
    is($args->{notUpdated}{nosuchcard}{type}, 'notFound', 'error type is notFound');
  };

  subtest "State advances after update" => sub {
    my $state_before = $account->get_state('contactCard');
    $tester->request([[
      "ContactCard/set" => {
        update => { $id => { 'name/full' => 'Alice State Check' } },
      },
    ]]);
    my $state_after = $account->get_state('contactCard');
    isnt($state_after, $state_before, 'state changed after update');
  };
};
