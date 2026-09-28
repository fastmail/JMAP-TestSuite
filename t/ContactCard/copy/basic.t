use jmaptest;

attr pristine  => 1;
attr pool_pairs => 1;

test {
  my ($self) = @_;

  my ($from_account, $to_account) = $self->pool_account_pair;
  my $from_tester = $from_account->tester;
  my $to_tester   = $to_account->tester;

  $from_tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:contacts',
  );

  # Skip unless the destination is usable for contacts at all: a Cyrus pool
  # pair shares mail, but AddressBook/get on the other account is
  # accountNotSupportedByMethod.
  my $probe = $from_tester->request([[
    "AddressBook/get" => { accountId => $to_account->accountId },
  ]])->single_sentence;

  if ($probe->name eq 'error') {
    pass("destination account is not usable for contacts ("
       . ($probe->arguments->{type} // 'unknown error')
       . "); skipping cross-account ContactCard/copy");
    return;
  }

  # Skip unless there is a writable address book there too; Cyrus shows the
  # grantee only a Default book with mayWriteAll false.
  unless (grep { $_->{myRights}{mayWriteAll} }
          @{ $probe->arguments->{list} // [] }) {
    pass("no writable address book in the destination account; "
       . "skipping cross-account ContactCard/copy");
    return;
  }

  my $src_card = $from_account->create_contact_card({
    name => { full => "Copy Test Contact $$" },
  });

  my $dest_ab = $to_account->create_address_book;

  my $res = $from_tester->request([[
    "ContactCard/copy" => {
      fromAccountId => $from_account->accountId,
      accountId     => $to_account->accountId,
      create => {
        c1 => {
          id              => $src_card->id,
          addressBookIds  => { $dest_ab->id => JSON::true },
        },
      },
    },
  ]]);
  ok($res->is_success, "ContactCard/copy") or diag explain $res->response_payload;

  jcmp_deeply(
    $res->single_sentence("ContactCard/copy")->arguments,
    {
      fromAccountId => jstr($from_account->accountId),
      accountId     => jstr($to_account->accountId),
      oldState      => jstr(),
      newState      => jstr(),
      created       => { c1 => superhashof({ id => jstr() }) },
      notCreated    => undef,
    },
    "ContactCard/copy response looks right",
  ) or diag explain $res->as_stripped_triples;

  my $new_id = $res->single_sentence("ContactCard/copy")->arguments->{created}{c1}{id};

  my $verify = $to_tester->request([[
    "ContactCard/get" => {
      accountId => $to_account->accountId,
      ids       => [ $new_id ],
    },
  ]]);
  my $got_card = $verify->single_sentence("ContactCard/get")->arguments->{list}[0];
  ok($got_card, "copied card exists in destination account")
    or diag explain $verify->as_stripped_triples;

  jcmp_deeply(
    $got_card->{addressBookIds},
    { $dest_ab->id => JSON::true },
    "card is in the destination address book",
  ) or diag explain $got_card;

  my $orig = $from_tester->request([[
    "ContactCard/get" => {
      accountId => $from_account->accountId,
      ids       => [ $src_card->id ],
    },
  ]]);
  ok(
    $orig->single_sentence("ContactCard/get")->arguments->{list}[0],
    "original card still exists in source account",
  );
};
