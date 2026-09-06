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

  subtest "Rename an address book" => sub {
    my $res = $tester->request([[
      "AddressBook/set" => {
        update => {
          $ab->id => { name => 'Renamed AddressBook' },
        },
      },
    ]]);
    ok($res->is_success, "AddressBook/set update name")
      or diag explain $res->response_payload;

    my $args = $res->single_sentence("AddressBook/set")->arguments;

    jcmp_deeply(
      $args,
      superhashof({
        accountId => jstr($account->accountId),
        oldState  => jstr(),
        newState  => jstr(),
        updated   => superhashof({ $ab->id => ignore() }),
      }),
      "update response looks good",
    ) or diag explain $res->as_stripped_triples;

    ok(!$args->{notUpdated}{ $ab->id }, 'not in notUpdated');

    my $get_res = $tester->request([[
      "AddressBook/get" => { ids => [$ab->id], properties => ['name'] },
    ]]);
    my $list = $get_res->single_sentence("AddressBook/get")->arguments->{list};
    is($list->[0]{name}, 'Renamed AddressBook', 'name updated');
  };

  subtest "Update notFound returns error" => sub {
    my $res = $tester->request([[
      "AddressBook/set" => {
        update => {
          'notarealid' => { name => 'Ghost' },
        },
      },
    ]]);
    ok($res->is_success, "AddressBook/set update unknown id");

    my $args = $res->single_sentence("AddressBook/set")->arguments;
    ok($args->{notUpdated}{notarealid}, 'unknown id in notUpdated');
    is($args->{notUpdated}{notarealid}{type}, 'notFound', 'correct error type');
  };

  subtest "State advances after update" => sub {
    my $state_before = $account->get_state('addressBook');

    $tester->request([[
      "AddressBook/set" => {
        update => { $ab->id => { name => 'State Test Updated' } },
      },
    ]]);

    my $state_after = $account->get_state('addressBook');

    isnt($state_after, $state_before, 'state changed after update');
  };
};
