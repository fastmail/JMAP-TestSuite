use jmaptest;


# We need to know that only our mailboxes here exist for predicting filter
# results, so we need a pristine account.
attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  my $mailbox1 = $account->create_mailbox;

  my $mailbox2 = $account->create_mailbox({
    parentId => $mailbox1->id,
  });

  subtest "parentId" => sub {

    subtest "does not have a parentId" => sub {
      my $res = $tester->request([[
        "Mailbox/query" => {
          filter => {
            parentId => undef,
          },
        },
      ]]);
      ok($res->is_success, "Mailbox/query")
        or diag explain $res->http_response->as_string;

      my $ids = $res->single_sentence("Mailbox/query")->arguments->{ids};

      jcmp_deeply($ids, supersetof($mailbox1->id), 'Got top-level mailbox');
      jcmp_deeply($ids, noneof($mailbox2->id), 'Did not get sub-mailbox');
    };

    subtest "has a parentId" => sub {
      my $res = $tester->request([[
        "Mailbox/query" => {
          filter => {
            parentId => $mailbox1->id,
          },
        },
      ]]);
      ok($res->is_success, "Mailbox/query")
        or diag explain $res->http_response->as_string;

      my $ids = $res->single_sentence("Mailbox/query")->arguments->{ids};

      jcmp_deeply($ids, [ $mailbox2->id ], 'Got our one child mailbox');
    };
  };

  subtest "hasAnyRole" => sub {
    # Find some mailboxes with roles
    my $res = $tester->request([[
      "Mailbox/get" => {},
    ]]);

    my @with_roles = map {;
      $_->{id}
    } grep {;
      $_->{role}
    } @{ $res->single_sentence("Mailbox/get")->arguments->{list} };

    plan skip_all => "No mailboxes with roles found, can't continue"
      unless @with_roles;

    subtest "false" => sub {
      my $res = $tester->request([[
        "Mailbox/query" => {
          filter => {
            hasAnyRole => JSON::false,
          },
        },
      ]]);
      ok($res->is_success, "Mailbox/query")
        or diag explain $res->http_response->as_string;

      my $ids = $res->single_sentence("Mailbox/query")->arguments->{ids};

      jcmp_deeply(
        $ids,
        supersetof($mailbox1->id, $mailbox2->id),
        'Got mailboxes with no roles',
      );

      jcmp_deeply(
        $ids,
        noneof(@with_roles),
        'Did not get mailboxes with roles',
      ) or diag explain $ids;
    };

    subtest "true" => sub {
      my $res = $tester->request([[
        "Mailbox/query" => {
          filter => {
            hasAnyRole => JSON::true,
          },
        },
      ]]);
      ok($res->is_success, "Mailbox/query")
        or diag explain $res->http_response->as_string;

      my $ids = $res->single_sentence("Mailbox/query")->arguments->{ids};

      jcmp_deeply($ids, \@with_roles, 'Got mailboxes with roles only');
    };
  };
};
