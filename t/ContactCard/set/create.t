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

  my $res = $tester->request([[
    "ContactCard/set" => {
      create => {
        c1 => {
          q(@type)       => 'Card',
          version        => '1.0',
          name           => { full => "Alice Example" },
          addressBookIds => { $ab->id => \1 },
          emails         => { e1 => { contexts => { work => \1 }, address => 'alice@example.com' } },
        },
      },
    },
  ]]);
  ok($res->is_success, "ContactCard/set create")
    or diag explain $res->response_payload;

  my $set_args = $res->single_sentence("ContactCard/set")->arguments;

  jcmp_deeply(
    $set_args,
    superhashof({
      accountId => jstr($account->accountId),
      oldState  => jstr(),
      newState  => jstr(),
      created   => superhashof({ c1 => superhashof({ id => jstr() }) }),
    }),
    "ContactCard/set response looks good",
  ) or diag explain $res->as_stripped_triples;

  my $id = $set_args->{created}{c1}{id};
  ok($id, 'got contact card id');

  subtest "Verify created card via get" => sub {
    my $get_res = $tester->request([[
      "ContactCard/get" => { ids => [$id] },
    ]]);
    ok($get_res->is_success, "ContactCard/get");

    my $list = $get_res->single_sentence("ContactCard/get")->arguments->{list};
    is(scalar @$list, 1, 'got 1 contact');
    is($list->[0]{id}, $id, 'id matches');
  };
};
