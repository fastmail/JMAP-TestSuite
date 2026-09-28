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
    'urn:ietf:params:jmap:mail',
  );

  my $upload = $from_tester->upload({
    accountId => $from_account->accountId,
    type      => 'text/plain',
    blob      => \"hello world",
  });
  my $blobId = $upload->blobId;

  my $res = $from_tester->request([[
    "Blob/copy" => {
      fromAccountId => $from_account->accountId,
      accountId     => $to_account->accountId,
      blobIds       => [ $blobId ],
    },
  ]]);
  ok($res->is_success, "Blob/copy") or diag explain $res->response_payload;

  # superhashof because RFC 8620 does not forbid a server adding response
  # properties of its own; Cyrus sends an undocumented oldState.
  jcmp_deeply(
    $res->single_sentence("Blob/copy")->arguments,
    superhashof({
      fromAccountId => jstr($from_account->accountId),
      accountId     => jstr($to_account->accountId),
      # S6.3 types copied as Id[Id]: old blobId to new blobId, not an object.
      copied    => { $blobId => jstr() },
      notCopied => undef,
    }),
    "Blob/copy response looks right",
  ) or diag explain $res->as_stripped_triples;

  subtest "copied email blob is usable in destination" => sub {
    my $email_blob = $from_account->email_blob(generic => {});

    my $copy_res = $from_tester->request([[
      "Blob/copy" => {
        fromAccountId => $from_account->accountId,
        accountId     => $to_account->accountId,
        blobIds       => [ $email_blob->blobId ],
      },
    ]]);
    ok($copy_res->is_success, "Blob/copy of email blob")
      or diag explain $copy_res->response_payload;

    my $new_blobId = $copy_res->single_sentence("Blob/copy")->arguments
      ->{copied}{$email_blob->blobId};
    ok($new_blobId, "got new blobId for email blob");

    my $mbox = $to_account->create_mailbox;
    my $import_res = $to_tester->request([[
      "Email/import" => {
        accountId => $to_account->accountId,
        emails => {
          e1 => {
            blobId     => $new_blobId,
            mailboxIds => { $mbox->id => JSON::true },
          },
        },
      },
    ]]);
    ok($import_res->is_success, "Email/import with copied blob")
      or diag explain $import_res->response_payload;

    jcmp_deeply(
      $import_res->single_sentence("Email/import")->arguments->{created},
      { e1 => superhashof({ id => jstr() }) },
      "email imported successfully using copied blob",
    ) or diag explain $import_res->as_stripped_triples;
  };

  subtest "notFound for unknown blob" => sub {
    my $res2 = $from_tester->request([[
      "Blob/copy" => {
        fromAccountId => $from_account->accountId,
        accountId     => $to_account->accountId,
        blobIds       => [ "f-nonexistent" ],
      },
    ]]);
    ok($res2->is_success, "Blob/copy with missing blob")
      or diag explain $res2->response_payload;

    jcmp_deeply(
      $res2->single_sentence("Blob/copy")->arguments,
      superhashof({
        fromAccountId => jstr($from_account->accountId),
        accountId     => jstr($to_account->accountId),
        copied    => undef,
        notCopied => { "f-nonexistent" => superhashof({ type => jstr() }) },
      }),
      "missing blob reported in notCopied",
    ) or diag explain $res2->as_stripped_triples;
  };
};
