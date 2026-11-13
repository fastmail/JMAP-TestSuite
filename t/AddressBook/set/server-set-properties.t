use jmaptest;
use Data::GUID qw(guid_string);

# RFC 9610 S2: isDefault and myRights are server-set. RFC 8620 S5.3: one
# given with a value "different to the current value" is invalidProperties,
# but passing back the current value "is not an error".

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:contacts',
  );

  my $no_rights = { map {; $_ => JSON::false } qw(mayRead mayWrite mayShare mayDelete) };

  subtest "create with myRights" => sub {
    my $res = $tester->request([[
      "AddressBook/set" => {
        create => { new => { name => "ServerSet " . guid_string(), myRights => $no_rights } },
      },
    ]]);
    ok($res->is_success, "AddressBook/set") or diag explain $res->response_payload;

    my $args = $res->single_sentence("AddressBook/set")->arguments;
    ok(!$args->{created}{new}, "not created") or diag explain $args;
    jcmp_deeply($args->{notCreated}{new}, invalid_properties('myRights'), "invalidProperties")
      or diag explain $args;
  };

  subtest "create with isDefault true while another book is the default" => sub {
    my $res = $tester->request([[
      "AddressBook/get" => { ids => undef, properties => [ 'isDefault' ] },
    ]]);
    unless (grep {; $_->{isDefault} } @{ $res->single_sentence("AddressBook/get")->arguments->{list} }) {
      note("no address book is the default; skipping");
      return;
    }

    $res = $tester->request([[
      "AddressBook/set" => {
        create => { new => { name => "ServerSet " . guid_string(), isDefault => JSON::true } },
      },
    ]]);
    ok($res->is_success, "AddressBook/set") or diag explain $res->response_payload;

    my $args = $res->single_sentence("AddressBook/set")->arguments;
    ok(!$args->{created}{new}, "not created") or diag explain $args;
    jcmp_deeply($args->{notCreated}{new}, invalid_properties('isDefault'), "invalidProperties")
      or diag explain $args;
  };

  my $ab = $account->create_address_book;
  my $get = $tester->request([[
    "AddressBook/get" => { ids => [ $ab->id ], properties => [ qw(isDefault myRights) ] },
  ]]);
  my $current = $get->single_sentence("AddressBook/get")->arguments->{list}[0];

  my %change = (
    isDefault => $current->{isDefault} ? JSON::false : JSON::true,
    'myRights/mayDelete' => $current->{myRights}{mayDelete} ? JSON::false : JSON::true,
  );

  for my $path (sort keys %change) {
    subtest "update changing $path" => sub {
      my $res = $tester->request([[
        "AddressBook/set" => { update => { $ab->id => { $path => $change{$path} } } },
      ]]);
      ok($res->is_success, "AddressBook/set") or diag explain $res->response_payload;

      my ($prop) = split m{/}, $path;
      my $args = $res->single_sentence("AddressBook/set")->arguments;
      ok(!exists(($args->{updated} // {})->{ $ab->id }), "not updated") or diag explain $args;
      jcmp_deeply($args->{notUpdated}{ $ab->id }, invalid_properties($prop), "invalidProperties")
        or diag explain $args;
    };
  }

  subtest "update passing back the current values" => sub {
    my $res = $tester->request([[
      "AddressBook/set" => {
        update => {
          $ab->id => {
            isDefault => $current->{isDefault},
            myRights  => $current->{myRights},
          },
        },
      },
    ]]);
    ok($res->is_success, "AddressBook/set") or diag explain $res->response_payload;

    my $args = $res->single_sentence("AddressBook/set")->arguments;
    ok(exists(($args->{updated} // {})->{ $ab->id }), "updated") or diag explain $args;
  };
};
