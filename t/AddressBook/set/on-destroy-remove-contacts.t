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
          name           => { full => "Test Contact" },
          addressBookIds => { $ab->id => \1 },
        },
      },
    },
  ]]);
  ok($res->is_success, "ContactCard/set create");
  my $card_id = $res->single_sentence("ContactCard/set")->arguments->{created}{c1}{id};
  ok($card_id, 'created contact card');

  subtest "Destroy without flag fails" => sub {
    my $res = $tester->request([[
      "AddressBook/set" => {
        destroy => [ $ab->id ],
      },
    ]]);
    ok($res->is_success, "AddressBook/set destroy request succeeds");

    my $args = $res->single_sentence("AddressBook/set")->arguments;
    ok($args->{notDestroyed}{ $ab->id }, 'address book not destroyed (has contacts)');
    is($args->{notDestroyed}{ $ab->id }{type}, 'addressBookHasContents',
       'correct error type');
  };

  subtest "Destroy with onDestroyRemoveContents succeeds" => sub {
    my $res = $tester->request([[
      "AddressBook/set" => {
        destroy                 => [ $ab->id ],
        onDestroyRemoveContents => \1,
      },
    ]]);
    ok($res->is_success, "AddressBook/set destroy with flag");

    my $args = $res->single_sentence("AddressBook/set")->arguments;
    ok(!$args->{notDestroyed}{ $ab->id }, 'no notDestroyed entry');
    ok(grep { $_ eq $ab->id } @{ $args->{destroyed} // [] }, 'address book destroyed');
  };
};
