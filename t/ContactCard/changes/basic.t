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
    my $state = $account->get_state('contactCard');

    my $res = $tester->request([[
      "ContactCard/changes" => { sinceState => $state },
    ]]);
    ok($res->is_success, "ContactCard/changes") or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("ContactCard/changes")->arguments,
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

  subtest "Created contact shows up in created" => sub {
    my $state = $account->get_state('contactCard');

    my $card = $account->create_contact_card;

    my $res = $tester->request([[
      "ContactCard/changes" => { sinceState => $state },
    ]]);
    ok($res->is_success, "ContactCard/changes") or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("ContactCard/changes")->arguments,
      superhashof({
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [ $card->id ],
        updated        => [],
        destroyed      => [],
      }),
      "created response looks good",
    );
  };

  subtest "Updated contact shows up in updated" => sub {
    my $card = $account->create_contact_card;
    my $state = $account->get_state('contactCard');

    $tester->request([[
      "ContactCard/set" => {
        update => {
          $card->id => { 'name/full' => 'Changes Test Updated' },
        },
      },
    ]]);

    my $res = $tester->request([[
      "ContactCard/changes" => { sinceState => $state },
    ]]);
    ok($res->is_success, "ContactCard/changes") or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("ContactCard/changes")->arguments,
      superhashof({
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [ $card->id ],
        destroyed      => [],
      }),
      "updated response looks good",
    );
  };

  subtest "Destroyed contact shows up in destroyed" => sub {
    my $card = $account->create_contact_card;
    my $state = $account->get_state('contactCard');

    $tester->request([[
      "ContactCard/set" => { destroy => [ $card->id ] },
    ]]);

    my $res = $tester->request([[
      "ContactCard/changes" => { sinceState => $state },
    ]]);
    ok($res->is_success, "ContactCard/changes") or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("ContactCard/changes")->arguments,
      superhashof({
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [],
        destroyed      => [ $card->id ],
      }),
      "destroyed response looks good",
    );
  };
};
