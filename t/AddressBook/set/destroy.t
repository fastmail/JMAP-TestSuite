use jmaptest;

# RFC 9610 S2.3: destroying an address book with contents is refused with
# "addressBookHasContents" unless "onDestroyRemoveContents" is set.

attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:contacts',
  );

  subtest "Destroy an empty address book" => sub {
    my $book = $account->create_address_book;
    my $id   = $book->id;

    my $res = $tester->request([[
      "AddressBook/set" => {
        destroy => [$id],
      },
    ]]);
    ok($res->is_success, "AddressBook/set destroy")
      or diag explain $res->response_payload;

    my $args = $res->single_sentence("AddressBook/set")->arguments;

    jcmp_deeply(
      $args,
      superhashof({
        accountId => jstr($account->accountId),
        oldState  => jstr(),
        newState  => jstr(),
        destroyed => [$id],
      }),
      "destroy response looks good",
    ) or diag explain $res->as_stripped_triples;

    ok(!$args->{notDestroyed}{$id}, 'not in notDestroyed');

    subtest "Verify gone via get" => sub {
      my $get_res = $tester->request([[
        "AddressBook/get" => { ids => [$id] },
      ]]);
      my $get_args = $get_res->single_sentence("AddressBook/get")->arguments;
      ok(grep { $_ eq $id } @{$get_args->{notFound}}, 'id in notFound after destroy');
      is(scalar @{$get_args->{list}}, 0, 'list is empty');
    };
  };

  subtest "Destroy address book with cards fails without onDestroyRemoveContents" => sub {
    my $book = $account->create_address_book;
    $account->create_contact_card({ addressBookIds => { $book->id => \1 } });

    my $res = $tester->request([[
      "AddressBook/set" => {
        destroy => [$book->id],
      },
    ]]);
    ok($res->is_success, "AddressBook/set destroy with cards");

    my $args = $res->single_sentence("AddressBook/set")->arguments;
    ok($args->{notDestroyed}{ $book->id }, 'address book with cards in notDestroyed');
    is($args->{notDestroyed}{ $book->id }{type}, 'addressBookHasContents',
       'correct error type');
    ok(!(grep { $_ eq $book->id } @{$args->{destroyed} // []}), 'not in destroyed');
  };

  subtest "Destroy address book with cards succeeds with onDestroyRemoveContents" => sub {
    my $book = $account->create_address_book;
    my $card = $account->create_contact_card({ addressBookIds => { $book->id => \1 } });

    my $res = $tester->request([[
      "AddressBook/set" => {
        destroy                 => [$book->id],
        onDestroyRemoveContents => \1,
      },
    ]]);
    ok($res->is_success, "AddressBook/set destroy with onDestroyRemoveContents")
      or diag explain $res->response_payload;

    my $args = $res->single_sentence("AddressBook/set")->arguments;
    ok(grep { $_ eq $book->id } @{$args->{destroyed} // []}, 'address book destroyed');
    ok(!$args->{notDestroyed}{ $book->id }, 'not in notDestroyed');

    subtest "Card also gone" => sub {
      # S2.3: only destroyed outright because it was in no other book.
      my $get_res = $tester->request([[
        "ContactCard/get" => { ids => [$card->id] },
      ]]);
      my $get_args = $get_res->single_sentence("ContactCard/get")->arguments;
      ok(grep { $_ eq $card->id } @{$get_args->{notFound}},
         'card in notFound after address book destroy');
    };
  };

  subtest "Card in a second address book survives" => sub {
    # RFC 9610 S2.1 requires a card to be in at least one address book but not
    # that a server support several, so skip if this create is refused.
    my $book1 = $account->create_address_book;
    my $book2 = $account->create_address_book;

    my $cres = $tester->request([[
      "ContactCard/set" => {
        create => {
          multi => {
            '@type'        => 'Card',
            version        => '1.0',
            name           => { full => "Multi-book contact $^T.$$" },
            addressBookIds => { $book1->id => \1, $book2->id => \1 },
          },
        },
      },
    ]]);
    ok($cres->is_success, "ContactCard/set create") or return;

    my $cargs = $cres->single_sentence("ContactCard/set")->arguments;

    unless ($cargs->{created}{multi}) {
      note('server will not put one card in two address books ('
         . ($cargs->{notCreated}{multi}{type} // 'unknown error')
         . '); RFC 9610 does not require it, so skipping');
      return;
    }

    my $card = $cargs->{created}{multi};

    my $res = $tester->request([[
      "AddressBook/set" => {
        destroy                 => [$book1->id],
        onDestroyRemoveContents => \1,
      },
    ]]);
    ok($res->is_success, "AddressBook/set destroy one of two books")
      or diag explain $res->response_payload;

    ok(grep { $_ eq $book1->id }
         @{ $res->single_sentence("AddressBook/set")->arguments->{destroyed} // [] },
       'first address book destroyed');

    my $get_res = $tester->request([[
      "ContactCard/get" => { ids => [ $card->{id} ] },
    ]]);
    my $get_args = $get_res->single_sentence("ContactCard/get")->arguments;

    is(scalar @{$get_args->{list}}, 1, 'card still exists')
      or diag explain $get_args;

    jcmp_deeply(
      $get_args->{list}[0]{addressBookIds},
      { $book2->id => jtrue() },
      'card now belongs only to the surviving address book',
    ) or diag explain $get_args->{list}[0]{addressBookIds};
  };

  subtest "Destroy unknown id returns notFound" => sub {
    my $res = $tester->request([[
      "AddressBook/set" => {
        destroy => ['notarealid'],
      },
    ]]);
    ok($res->is_success, "AddressBook/set destroy unknown id");

    my $args = $res->single_sentence("AddressBook/set")->arguments;
    ok($args->{notDestroyed}{notarealid}, 'unknown id in notDestroyed');
    is($args->{notDestroyed}{notarealid}{type}, 'notFound', 'correct error type');
  };

  subtest "State advances after destroy" => sub {
    my $book = $account->create_address_book;

    my $state_before = $tester->request([[
      "AddressBook/get" => { ids => [] },
    ]])->single_sentence("AddressBook/get")->arguments->{state};

    $tester->request([[
      "AddressBook/set" => { destroy => [$book->id] },
    ]]);

    my $state_after = $tester->request([[
      "AddressBook/get" => { ids => [] },
    ]])->single_sentence("AddressBook/get")->arguments->{state};

    isnt($state_after, $state_before, 'state changed after destroy');
  };
};
