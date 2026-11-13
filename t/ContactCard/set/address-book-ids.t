use jmaptest;
use Data::GUID qw(guid_string);

# RFC 9610 S3: a card "MUST belong to at least one AddressBook at all times",
# and each value in addressBookIds "MUST be true".

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:contacts',
  );

  my $ab1 = $account->create_address_book;
  my $ab2 = $account->create_address_book;

  my $card = sub {
    my ($ids) = @_;
    return {
      '@type'        => 'Card',
      version        => '1.0',
      uid            => "urn:uuid:" . lc guid_string(),
      name           => { full => "AddressBookIds Test" },
      addressBookIds => $ids,
    };
  };

  # RFC 8620 S5.3: an id that "does not correspond to a valid record" is
  # invalidProperties too.
  my %bad = (
    'empty set'        => {},
    'unknown book'     => { 'no-such-address-book' => \1 },
    'value false'      => { $ab1->id => \0 },
  );

  for my $what (sort keys %bad) {
    subtest "create with addressBookIds $what" => sub {
      my $res = $tester->request([[
        "ContactCard/set" => { create => { c1 => $card->($bad{$what}) } },
      ]]);
      ok($res->is_success, "ContactCard/set") or diag explain $res->response_payload;

      my $args = $res->single_sentence("ContactCard/set")->arguments;
      ok(!$args->{created}{c1}, "card not created") or diag explain $args;
      jcmp_deeply(
        $args->{notCreated}{c1},
        invalid_properties('addressBookIds'),
        "rejected with invalidProperties",
      ) or diag explain $args;
    };
  }

  my $res = $tester->request([[
    "ContactCard/set" => { create => { c1 => $card->({ $ab1->id => \1 }) } },
  ]]);
  my $id = $res->single_sentence("ContactCard/set")->arguments->{created}{c1}{id};
  ok($id, "created a card in one address book") or diag explain $res->as_stripped_triples;

  my $book_ids_of = sub {
    my $get = $tester->request([[
      "ContactCard/get" => { ids => [ $id ], properties => [ 'addressBookIds' ] },
    ]]);
    return $get->single_sentence("ContactCard/get")->arguments->{list}[0]{addressBookIds};
  };

  subtest "update removing the only address book" => sub {
    my $res = $tester->request([[
      "ContactCard/set" => {
        update => { $id => { 'addressBookIds/' . $ab1->id => undef } },
      },
    ]]);
    ok($res->is_success, "ContactCard/set") or diag explain $res->response_payload;

    my $args = $res->single_sentence("ContactCard/set")->arguments;
    ok(!$args->{updated}{$id}, "card not updated") or diag explain $args;
    jcmp_deeply(
      $args->{notUpdated}{$id},
      invalid_properties('addressBookIds'),
      "rejected with invalidProperties",
    ) or diag explain $args;

    jcmp_deeply($book_ids_of->(), { $ab1->id => jtrue }, "card still in its book");
  };

  subtest "move the card to another address book" => sub {
    my $res = $tester->request([[
      "ContactCard/set" => {
        update => {
          $id => {
            'addressBookIds/' . $ab1->id => undef,
            'addressBookIds/' . $ab2->id => \1,
          },
        },
      },
    ]]);
    ok($res->is_success, "ContactCard/set") or diag explain $res->response_payload;

    my $args = $res->single_sentence("ContactCard/set")->arguments;
    ok(exists $args->{updated}{$id}, "card updated") or diag explain $args;

    jcmp_deeply($book_ids_of->(), { $ab2->id => jtrue }, "card is now only in the second book");
  };
};
