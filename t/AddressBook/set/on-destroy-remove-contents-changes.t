use jmaptest;

# RFC 9610 S2.3: with onDestroyRemoveContents, a card in the destroyed book
# "will be removed from it, and if such a ContactCard does not belong to any
# other AddressBook, it will be destroyed".

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:contacts',
  );

  my $doomed = $account->create_address_book;
  my $other  = $account->create_address_book;

  my $only = $account->create_contact_card({
    name         => { full => "Only In Doomed Book" },
    address_book => $doomed,
  });
  my $both = $account->create_contact_card({
    name           => { full => "In Both Books" },
    addressBookIds => { $doomed->id => \1, $other->id => \1 },
    address_book   => $other,
  });

  my $state = $account->get_state('contactCard');

  my $res = $tester->request([[
    "AddressBook/set" => {
      destroy                 => [ $doomed->id ],
      onDestroyRemoveContents => JSON::true,
    },
  ]]);
  ok($res->is_success, "AddressBook/set destroy") or diag explain $res->response_payload;
  jcmp_deeply(
    $res->single_sentence("AddressBook/set")->arguments->{destroyed},
    [ $doomed->id ],
    "address book destroyed",
  ) or diag explain $res->as_stripped_triples;

  my $changes = $tester->request([[
    "ContactCard/changes" => { sinceState => $state },
  ]]);
  ok($changes->is_success, "ContactCard/changes") or diag explain $changes->response_payload;

  jcmp_deeply(
    $changes->single_sentence("ContactCard/changes")->arguments,
    superhashof({
      oldState       => jstr($state),
      newState       => none(jstr($state)),
      hasMoreChanges => jfalse,
      created        => [],
      updated        => [ $both->id ],
      destroyed      => [ $only->id ],
    }),
    "the card only in the book is destroyed, the other is updated",
  ) or diag explain $changes->as_stripped_triples;

  my $get = $tester->request([[
    "ContactCard/get" => { ids => [ $only->id, $both->id ], properties => [ 'addressBookIds' ] },
  ]]);
  my $args = $get->single_sentence("ContactCard/get")->arguments;
  jcmp_deeply($args->{notFound}, [ $only->id ], "the card only in the book is gone");
  jcmp_deeply(
    $args->{list},
    [ superhashof({ id => $both->id, addressBookIds => { $other->id => jtrue } }) ],
    "the other card is left in its other book",
  ) or diag explain $args;
};
