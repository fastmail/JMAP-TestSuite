use jmaptest;

attr pristine   => 1;
attr pool_pairs => 1;

# RFC 9610 S3: "there MUST NOT be more than one ContactCard with the same uid
# in an Account", so a second copy of one card into the same account fails.

test {
  my ($self) = @_;

  my ($from_account, $to_account) = $self->pool_account_pair;
  my $from_tester = $from_account->tester;

  $from_tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:contacts',
  );

  my $probe = $from_tester->request([[
    "AddressBook/get" => { accountId => $to_account->accountId },
  ]])->single_sentence;

  if ($probe->name eq 'error') {
    pass("destination account is not usable for contacts ("
       . ($probe->arguments->{type} // 'unknown error')
       . "); skipping cross-account ContactCard/copy");
    return;
  }

  unless (grep { $_->{myRights}{mayWrite} || $_->{myRights}{mayWriteAll} }
          @{ $probe->arguments->{list} // [] }) {
    pass("no writable address book in the destination account; "
       . "skipping cross-account ContactCard/copy");
    return;
  }

  my $src_card = $from_account->create_contact_card({
    name => { full => "Copy Uid Test $$" },
  });
  my $dest_ab = $to_account->create_address_book;

  my $copy = sub {
    my $res = $from_tester->request([[
      "ContactCard/copy" => {
        fromAccountId => $from_account->accountId,
        accountId     => $to_account->accountId,
        create => {
          c1 => {
            id             => $src_card->id,
            addressBookIds => { $dest_ab->id => JSON::true },
          },
        },
      },
    ]]);
    ok($res->is_success, "ContactCard/copy") or diag explain $res->response_payload;
    return $res->single_sentence("ContactCard/copy")->arguments;
  };

  my $first = $copy->();
  my $first_id = $first->{created}{c1}{id};
  ok($first_id, "first copy created") or diag explain $first;
  return unless $first_id;

  my $second = $copy->();
  ok(!$second->{created}{c1}, "second copy not created") or diag explain $second;

  # RFC 8620 S5.4: alreadyExists "MUST" carry the existing record's id.
  jcmp_deeply(
    $second->{notCreated}{c1},
    any(
      superhashof({ type => 'alreadyExists', existingId => jstr($first_id) }),
      all(superhashof({ type => jstr }), code(sub { $_[0]{type} ne 'alreadyExists' })),
    ),
    "second copy rejected, with existingId if alreadyExists",
  ) or diag explain $second;
};
