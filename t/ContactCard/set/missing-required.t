use jmaptest;

use Data::GUID qw(guid_string);

# RFC 9610 S2: "A card MUST belong to at least one AddressBook at all times",
# and addressBookIds has no default the server is told to supply.  A create
# without it is rejected with invalidProperties naming addressBookIds; a
# server that files the card somewhere instead must leave it in a book.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:contacts',
  );

  $account->create_address_book;   # so there is somewhere it could go

  my $args = $tester->request([[
    "ContactCard/set" => {
      create => {
        c => {
          q(@type) => 'Card',
          version  => '1.0',
          uid      => "urn:uuid:" . lc guid_string(),
          name     => { full => "No address book" },
        },
      },
    },
  ]])->single_sentence("ContactCard/set")->arguments;

  if (my $err = $args->{notCreated}{c}) {
    jcmp_deeply($err, superhashof({ type => 'invalidProperties', properties => supersetof('addressBookIds') }),
      "rejected: invalidProperties naming addressBookIds") or diag explain $err;
    return;
  }

  my $id = $args->{created}{c}{id};
  ok($id, "created instead") or return diag explain $args;
  my $card = $tester->request([[
    "ContactCard/get" => { ids => [ $id ], properties => [ 'addressBookIds' ] },
  ]])->single_sentence("ContactCard/get")->arguments->{list}[0];
  ok($card && keys %{ $card->{addressBookIds} || {} },
     "then the card is in at least one address book") or diag explain $card;
};
