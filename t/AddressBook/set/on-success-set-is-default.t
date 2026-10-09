use jmaptest;

# RFC 9610 S2.3: a default change refused for policy reasons "MUST be
# ignored" and "No error is returned to the client".

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

  subtest "Set ab1 as default" => sub {
    my $res = $tester->request([[
      "AddressBook/set" => {
        onSuccessSetIsDefault => $ab1->id,
      },
    ]]);
    ok($res->is_success, "AddressBook/set onSuccessSetIsDefault");
    is($res->single_sentence->name, "AddressBook/set", "no error returned");

    my $get_res = $tester->request([[
      "AddressBook/get" => { ids => [ $ab1->id, $ab2->id ] },
    ]]);
    my %by_id = map { $_->{id} => $_ }
      @{ $get_res->single_sentence("AddressBook/get")->arguments->{list} };

    unless ($by_id{ $ab1->id }{isDefault}) {
      note('server did not make ab1 the default; S2.3 permits this, skipping');
      return;
    }

    ok(!$by_id{ $ab2->id }{isDefault}, 'ab2 is not default');
  };

  subtest "Switch default to ab2" => sub {
    my $res = $tester->request([[
      "AddressBook/set" => {
        onSuccessSetIsDefault => $ab2->id,
      },
    ]]);
    ok($res->is_success, "AddressBook/set switch default");
    is($res->single_sentence->name, "AddressBook/set", "no error returned");

    my $get_res = $tester->request([[
      "AddressBook/get" => { ids => [ $ab1->id, $ab2->id ] },
    ]]);
    my %by_id = map { $_->{id} => $_ }
      @{ $get_res->single_sentence("AddressBook/get")->arguments->{list} };

    unless ($by_id{ $ab2->id }{isDefault}) {
      note('server did not make ab2 the default; S2.3 permits this, skipping');
      return;
    }

    ok(!$by_id{ $ab1->id }{isDefault}, 'ab1 is no longer default');
  };
};
