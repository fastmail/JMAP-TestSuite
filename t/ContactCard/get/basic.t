use jmaptest;

use JMAP::TestSuite::Util qw(contact_card);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:contacts',
  );

  my $card = $account->create_contact_card;

  ok($card->id,  'contact card has an id');
  ok($card->uid, 'contact card has a uid');

  my $res = $tester->request([[
    "ContactCard/get" => { ids => [ $card->id ] },
  ]]);
  ok($res->is_success, "ContactCard/get")
    or diag explain $res->response_payload;

  jcmp_deeply(
    $res->single_sentence("ContactCard/get")->arguments,
    superhashof({
      accountId => jstr($account->accountId),
      state     => jstr(),
      notFound  => [],
      list      => [
        contact_card({ id => $card->id }),
      ],
    }),
    "ContactCard/get response looks good",
  ) or diag explain $res->as_stripped_triples;
};
