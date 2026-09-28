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

  my $name = "Test AB " . guid_string();

  my $res = $tester->request([[
    "AddressBook/set" => {
      create => {
        new => { name => $name },
      },
    },
  ]]);
  ok($res->is_success, "AddressBook/set create")
    or diag explain $res->response_payload;

  my $set_args = $res->single_sentence("AddressBook/set")->arguments;

  jcmp_deeply(
    $set_args,
    superhashof({
      accountId => jstr($account->accountId),
      oldState  => jstr(),
      newState  => jstr(),
      created   => superhashof({ new => superhashof({ id => jstr() }) }),
    }),
    "AddressBook/set response looks good",
  ) or diag explain $res->as_stripped_triples;

  my $id = $set_args->{created}{new}{id};
  ok($id, 'got new address book id');

  my $get_res = $tester->request([[
    "AddressBook/get" => { ids => [$id] },
  ]]);
  ok($get_res->is_success, "AddressBook/get after create");

  my $list = $get_res->single_sentence("AddressBook/get")->arguments->{list};
  is(scalar @$list, 1, 'got 1 address book');
  is($list->[0]{name}, $name, 'name matches');
};
