use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:contacts',
  );

  subtest "No changes returns same state" => sub {
    my $state = $account->get_state('addressBook');

    my $res = $tester->request([[
      "AddressBook/changes" => { sinceState => $state },
    ]]);
    ok($res->is_success, "AddressBook/changes") or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("AddressBook/changes")->arguments,
      superhashof({
        accountId      => jstr($account->accountId),
        oldState       => jstr($state),
        newState       => jstr($state),
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [],
        destroyed      => [],
      }),
      "no-changes response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "Created address book shows up in created" => sub {
    my $state = $account->get_state('addressBook');

    my $ab = $account->create_address_book;

    my $res = $tester->request([[
      "AddressBook/changes" => { sinceState => $state },
    ]]);
    ok($res->is_success, "AddressBook/changes") or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("AddressBook/changes")->arguments,
      superhashof({
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [ $ab->id ],
        updated        => [],
        destroyed      => [],
      }),
      "created response looks good",
    );
  };

  subtest "Updated address book shows up in updated" => sub {
    my $ab = $account->create_address_book;
    my $state = $account->get_state('addressBook');

    $tester->request([[
      "AddressBook/set" => {
        update => { $ab->id => { name => 'Changes Test Updated' } },
      },
    ]]);

    my $res = $tester->request([[
      "AddressBook/changes" => { sinceState => $state },
    ]]);
    ok($res->is_success, "AddressBook/changes") or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("AddressBook/changes")->arguments,
      superhashof({
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [ $ab->id ],
        destroyed      => [],
      }),
      "updated response looks good",
    );
  };

  subtest "Destroyed address book shows up in destroyed" => sub {
    my $ab = $account->create_address_book;
    my $state = $account->get_state('addressBook');

    $tester->request([[
      "AddressBook/set" => { destroy => [ $ab->id ] },
    ]]);

    my $res = $tester->request([[
      "AddressBook/changes" => { sinceState => $state },
    ]]);
    ok($res->is_success, "AddressBook/changes") or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("AddressBook/changes")->arguments,
      superhashof({
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [],
        destroyed      => [ $ab->id ],
      }),
      "destroyed response looks good",
    );
  };
};
