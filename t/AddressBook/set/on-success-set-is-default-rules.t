use jmaptest;
use Data::GUID qw(guid_string);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:contacts',
  );

  # RFC 9610 S2: isDefault "MUST NOT be true for more than one AddressBook".
  my $default_id = sub {
    my $res = $tester->request([[
      "AddressBook/get" => { ids => undef, properties => [ 'isDefault' ] },
    ]]);
    my @defaults = grep {; $_->{isDefault} }
      @{ $res->single_sentence("AddressBook/get")->arguments->{list} };
    ok(@defaults <= 1, "at most one address book is the default")
      or diag explain \@defaults;
    return @defaults ? $defaults[0]{id} : undef;
  };

  my $original = $default_id->();
  my $ab = $account->create_address_book;

  # RFC 9610 S2.3: an id that "is not found ... MUST be ignored", and "No
  # error is returned to the client".
  subtest "unknown id is ignored" => sub {
    my $res = $tester->request([[
      "AddressBook/set" => { onSuccessSetIsDefault => 'no-such-address-book' },
    ]]);
    ok($res->is_success, "AddressBook/set") or diag explain $res->response_payload;
    is($res->single_sentence->name, 'AddressBook/set', "no error returned")
      or diag explain $res->as_stripped_triples;

    my $args = $res->single_sentence->arguments;
    ok(!$args->{notUpdated} && !$args->{notCreated} && !$args->{notDestroyed},
       "no SetErrors") or diag explain $args;

    is($default_id->(), $original, "the default is unchanged");
  };

  # RFC 9610 S2.3: the default is only changed if "all creates, updates, and
  # destroys (if any) succeed without error".
  subtest "not applied when another change fails" => sub {
    my $res = $tester->request([[
      "AddressBook/set" => {
        update => { 'no-such-address-book' => { name => 'Ghost' } },
        onSuccessSetIsDefault => $ab->id,
      },
    ]]);
    ok($res->is_success, "AddressBook/set") or diag explain $res->response_payload;

    my $args = $res->single_sentence("AddressBook/set")->arguments;
    ok($args->{notUpdated}{'no-such-address-book'}, "the update failed")
      or diag explain $args;
    ok(!exists(($args->{updated} // {})->{ $ab->id }), "the address book is not reported updated")
      or diag explain $args;

    is($default_id->(), $original, "the default is unchanged");
  };

  # RFC 9610 S2.3: a creation is referred to as "#" plus its creation id, and
  # a changed default "MUST" be reported with the server-set value.
  subtest "creation reference" => sub {
    my $res = $tester->request([[
      "AddressBook/set" => {
        create => { new => { name => "Default Test " . guid_string() } },
        onSuccessSetIsDefault => '#new',
      },
    ]]);
    ok($res->is_success, "AddressBook/set") or diag explain $res->response_payload;

    my $args = $res->single_sentence("AddressBook/set")->arguments;
    my $id = $args->{created}{new}{id};
    ok($id, "address book created") or diag explain $args;

    my $now = $default_id->();
    unless (defined $now && $now eq $id) {
      note("server did not make the new address book the default; S2.3 permits this");
      return;
    }

    jcmp_deeply(
      $args->{created}{new},
      superhashof({ isDefault => jtrue }),
      "created reports isDefault true",
    ) or diag explain $args;

    if (defined $original) {
      jcmp_deeply(
        $args->{updated},
        superhashof({ $original => superhashof({ isDefault => jfalse }) }),
        "the old default is reported updated with isDefault false",
      ) or diag explain $args;
    }
  };

  if (defined $original && ($default_id->() // '') ne $original) {
    $tester->request([[
      "AddressBook/set" => { onSuccessSetIsDefault => $original },
    ]]);
  }
};
