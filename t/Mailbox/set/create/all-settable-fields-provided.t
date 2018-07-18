use jmaptest;

use Data::GUID qw(guid_string);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $new_name = guid_string();

  my $parent = $account->create_mailbox;

  # We should have state after creating a parent mailbox
  my $state = $account->get_state('mailbox');

  # XXX - Create with role test -- alh, 2018-02-22

  my $res = $tester->request({
    methodCalls => [[
      "Mailbox/set" => {
        create => {
          new => {
            name      => $new_name,
            parentId  => $parent->id,
            sortOrder => 55,
          },
        },
      },
    ]],
  });
  ok($res->is_success, "Mailbox/set create")
    or diag explain $res->http_response->as_string;

  jcmp_deeply(
    $res->single_sentence("Mailbox/set")->arguments,
    superhashof({
      accountId => jstr($account->accountId),
      newState  => jstr(),
      oldState  => jstr($state),
    }),
    "Set response looks good",
  );

  my $created =
    $res->single_sentence("Mailbox/set")->arguments->{created}{new};

  ok($created, 'created a new mailbox');

  my $id = $res->single_sentence("Mailbox/set")->as_set->created_id('new');
  ok($id, 'got a new id');

  # Server does not have to return fields, but does need to return id
  jcmp_deeply(
    $created,
    superhashof({
      id           => jstr(),
    }),
    "Our mailbox looks good"
  ) or diag explain $res->as_stripped_triples;

  subtest "Confirm our name is good" => sub {
    my $res = $tester->request({
      methodCalls => [[
        "Mailbox/get" => {
          ids => [ $id ],
          properties => [ 'name', 'parentId', 'sortOrder' ],
        },
      ]],
    });
    ok($res->is_success, "Mailbox/get")
      or diag explain $res->http_response->as_string;

    my @found = @{ $res->single_sentence("Mailbox/get")->arguments->{list} };
    is(@found, 1, 'got only 1 mailbox');

    jcmp_deeply(
      $found[0],
      superhashof({
        id        => jstr($id),
        name      => jstr($new_name),
        parentId  => jstr($parent->id),
        sortOrder => jnum(55),
      }),
      "Our mailbox settings looks good"
    ) or diag explain $res->as_stripped_triples;
  };
};
