use jmaptest;
use Data::GUID qw(guid_string);

# RFC 9610 S3: "there MUST NOT be more than one ContactCard with the same uid
# in an Account".

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
  my $uid = "urn:uuid:" . lc guid_string();

  my $first = $account->create_contact_card({
    uid          => $uid,
    name         => { full => "Uid Test One" },
    address_book => $ab1,
  });

  my $res = $tester->request([[
    "ContactCard/set" => {
      create => {
        c2 => {
          '@type'        => 'Card',
          version        => '1.0',
          uid            => $uid,
          name           => { full => "Uid Test Two" },
          addressBookIds => { $ab2->id => \1 },
        },
      },
    },
  ]]);
  ok($res->is_success, "ContactCard/set") or diag explain $res->response_payload;

  my $args = $res->single_sentence("ContactCard/set")->arguments;
  ok(!$args->{created}{c2}, "second card with the same uid not created")
    or diag explain $args;
  jcmp_deeply(
    $args->{notCreated}{c2},
    superhashof({ type => jstr }),
    "rejected with a SetError",
  ) or diag explain $args;

  my $get = $tester->request([[
    "ContactCard/get" => { ids => [ $first->id ], properties => [ 'uid', 'name' ] },
  ]]);
  is(
    $get->single_sentence("ContactCard/get")->arguments->{list}[0]{name}{full},
    "Uid Test One",
    "the existing card is unchanged",
  ) or diag explain $get->as_stripped_triples;
};
