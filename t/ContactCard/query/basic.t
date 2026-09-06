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
    name           => { full => "Alice Query" },
    addressBookIds => { $ab->id => \1 },
  });
  my $card2 = $account->create_contact_card({
    name           => { full => "Bob Query" },
    addressBookIds => { $ab->id => \1 },
  });

  subtest "Query all cards in address book" => sub {
    my $res = $tester->request([[
      "ContactCard/query" => {
        filter => { inAddressBook => $ab->id },
      },
    ]]);
    ok($res->is_success, "ContactCard/query")
      or diag explain $res->response_payload;

    my $args = $res->single_sentence("ContactCard/query")->arguments;
    ok(defined $args->{queryState}, 'has queryState');

    my %ids = map { $_ => 1 } @{ $args->{ids} // [] };
    ok($ids{ $card1->id }, 'card1 in results');
    ok($ids{ $card2->id }, 'card2 in results');
  };

  subtest "Empty ids for empty address book" => sub {
    my $empty_ab = $account->create_address_book;

    my $res = $tester->request([[
      "ContactCard/query" => {
        filter => { inAddressBook => $empty_ab->id },
      },
    ]]);
    ok($res->is_success, "ContactCard/query empty");

    my $args = $res->single_sentence("ContactCard/query")->arguments;
    is(scalar @{ $args->{ids} // [] }, 0, 'no results for empty address book');
  };
};
