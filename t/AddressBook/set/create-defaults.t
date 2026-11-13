use jmaptest;
use Data::GUID qw(guid_string);

# RFC 8620 S5.3: "created" holds every property "not sent by the client",
# including "all server-set properties" and those "set to a default".

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:contacts',
  );

  my $res = $tester->request([[
    "AddressBook/set" => {
      create => { new => { name => "Defaults " . guid_string() } },
    },
  ]]);
  ok($res->is_success, "AddressBook/set") or diag explain $res->response_payload;

  my $created = $res->single_sentence("AddressBook/set")->arguments->{created}{new};
  ok($created, "address book created") or diag(explain($res->as_stripped_triples)), return;

  # RFC 9610 S2 gives the defaults for description, sortOrder and shareWith.
  jcmp_deeply(
    $created,
    superhashof({
      id           => jstr,
      isDefault    => jbool,
      myRights     => superhashof({ map {; $_ => jbool } qw(mayRead mayWrite mayShare mayDelete) }),
      isSubscribed => jbool,
      description  => undef,
      sortOrder    => jnum(0),
      shareWith    => undef,
    }),
    "created has the server-set and defaulted properties",
  ) or diag explain $created;

  my $get = $tester->request([[
    "AddressBook/get" => { ids => [ $created->{id} ] },
  ]]);
  my $got = $get->single_sentence("AddressBook/get")->arguments->{list}[0];
  for my $prop (grep {; exists $created->{$_} } sort keys %$got) {
    jcmp_deeply($created->{$prop}, $got->{$prop}, "created $prop matches AddressBook/get");
  }
};
