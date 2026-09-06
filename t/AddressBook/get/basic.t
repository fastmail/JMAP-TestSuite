use jmaptest;

use JMAP::TestSuite::Util qw(address_book);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:contacts',
  );

  my $ab = $account->create_address_book;

  ok($ab->id,   'address book has an id');
  ok($ab->name, 'address book has a name');

  my $res = $tester->request([[
    "AddressBook/get" => { ids => [ $ab->id ] },
  ]]);
  ok($res->is_success, "AddressBook/get")
    or diag explain $res->response_payload;

  jcmp_deeply(
    $res->single_sentence("AddressBook/get")->arguments,
    superhashof({
      accountId => jstr($account->accountId),
      state     => jstr(),
      notFound  => [],
      list      => [
        address_book({
          id   => $ab->id,
          name => $ab->name,
        }),
      ],
    }),
    "AddressBook/get response looks good",
  ) or diag explain $res->as_stripped_triples;
};
