use jmaptest;

# draft-ietf-jmap-blobext Section 4: Blob/set creates, touches and destroys
# blobs under urn:ietf:params:jmap:blob2.

attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  # A client MUST NOT list both blob and blob2 in "using" (Section 2.1).
  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
    'urn:ietf:params:jmap:blob2',
  );

  my ($blobId, $concatId);
  subtest "create" => sub {
    my $res = $tester->request([[
      "Blob/set" => {
        create => {
          b1 => { data => [ { 'data:asText' => "Hello, world!" } ], type => 'text/plain' },
          b2 => { data => [ { 'data:asText' => "Hello, " }, { blobId => '#b1', offset => 7, length => 6 } ] },
        },
      },
    ]]);
    ok($res->is_success, "Blob/set") or diag explain $res->response_payload;
    my $args = $res->single_sentence("Blob/set")->arguments;
    jcmp_deeply(
      $args->{created}{b1},
      superhashof({ id => jstr(), size => jnum(13) }),
      "created BlobObject has id and size",
    ) or diag explain $args;
    jcmp_deeply($args->{created}{b2}, superhashof({ size => jnum(13) }), "a source referencing #b1 in the same call")
      or diag explain $args;
    $blobId   = $args->{created}{b1}{id};
    $concatId = $args->{created}{b2}{id};
    ok(!$args->{notCreated}, "nothing failed");

    my $get = $tester->request([[ "Blob/get" => { ids => [ $concatId ], properties => ['data:asText'] } ]]);
    is($get->single_sentence("Blob/get")->arguments->{list}[0]{'data:asText'}, "Hello, world!", "the concatenation is right");
  };

  subtest "a DataSourceObject whose size or digest does not match is rejected" => sub {
    my $res = $tester->request([[
      "Blob/set" => {
        create => {
          wrongsize => { data => [ { blobId => $blobId, size => 999 } ] },
          wrongpos  => { data => [ { 'data:asText' => 'x' }, { blobId => $blobId, position => 42 } ] },
        },
      },
    ]]);
    my $args = $res->single_sentence("Blob/set")->arguments;
    ok($args->{notCreated}{wrongsize}, "size that does not match the data: notCreated") or diag explain $args;
    ok($args->{notCreated}{wrongpos},  "position that does not match: notCreated") or diag explain $args;
  };

  subtest "update touches a blob" => sub {
    my $res = $tester->request([[
      "Blob/set" => { update => { $blobId => { expires => '2099-01-01T00:00:00Z' }, 'nosuchblob' => { expires => undef } } },
    ]]);
    ok($res->is_success, "Blob/set update") or diag explain $res->response_payload;
    my $args = $res->single_sentence("Blob/set")->arguments;
    ok(exists $args->{updated}{$blobId}, "the blob is in updated") or diag explain $args;
    jcmp_deeply($args->{notUpdated}{nosuchblob}, superhashof({ type => jstr('notFound') }),
      "an unknown blobId MUST be reported in notUpdated with notFound") or diag explain $args;

    $res = $tester->request([[
      "Blob/set" => { update => { $blobId => { size => 1 } } },
    ]]);
    $args = $res->single_sentence("Blob/set")->arguments;
    ok($args->{notUpdated}{$blobId}, "changing anything but expires is refused") or diag explain $args;
  };

  subtest "destroy" => sub {
    my $mailbox = $account->create_mailbox;
    my $email   = $mailbox->add_message;
    my $res = $tester->request([[
      "Blob/set" => { destroy => [ $concatId, $email->blobId, 'nosuchblob' ] },
    ]]);
    ok($res->is_success, "Blob/set destroy") or diag explain $res->response_payload;
    my $args = $res->single_sentence("Blob/set")->arguments;
    # b1 may still be referenced: blobext lets the server store b2 as a range
    # of it. Nothing was built from b2.
    jcmp_deeply($args->{destroyed}, [ $concatId ], "an unreferenced blob is destroyed") or diag explain $args;
    jcmp_deeply($args->{notDestroyed}{ $email->blobId }, superhashof({ type => jstr('blobHasReference') }),
      "a blob still referenced by an Email MUST be refused with blobHasReference") or diag explain $args;
    ok($args->{notDestroyed}{nosuchblob}, "an unknown blobId is notDestroyed");

    my $get = $tester->request([[ "Blob/get" => { ids => [ $concatId ], properties => ['size'] } ]]);
    jcmp_deeply($get->single_sentence("Blob/get")->arguments->{notFound}, [ $concatId ], "the destroyed blob is gone");
  };
};
