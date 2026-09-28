use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:contacts',
  );

  my $card = $account->create_contact_card;
  ok($card->id, 'created contact card');

  my $res = $tester->request([[
    "ContactCard/set" => {
      destroy => [ $card->id ],
    },
  ]]);
  ok($res->is_success, "ContactCard/set destroy")
    or diag explain $res->response_payload;

  my $set_args = $res->single_sentence("ContactCard/set")->arguments;

  ok(grep { $_ eq $card->id } @{ $set_args->{destroyed} // [] },
    'card id appears in destroyed list');

  ok(!$set_args->{notDestroyed}{ $card->id }, 'no notDestroyed entry');

  subtest "Card no longer returned by get" => sub {
    my $get_res = $tester->request([[
      "ContactCard/get" => { ids => [ $card->id ] },
    ]]);
    ok($get_res->is_success, "ContactCard/get");

    my $args = $get_res->single_sentence("ContactCard/get")->arguments;
    is(scalar @{ $args->{list} }, 0, 'no cards returned');
    ok(grep { $_ eq $card->id } @{ $args->{notFound} // [] }, 'card is in notFound');
  };
};
