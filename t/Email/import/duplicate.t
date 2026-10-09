use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mbox_1 = $account->create_mailbox;
  my $mbox_2 = $account->create_mailbox;
  my $blob   = $account->email_blob(generic => { subject => "duplicate $$" });
  ok($blob->is_success, "uploaded a message");

  my $import = sub {
    my ($mbox) = @_;
    my $res = $tester->request([[
      "Email/import" => {
        emails => {
          new => { blobId => $blob->blobId, mailboxIds => { $mbox->id => jtrue } },
        },
      },
    ]]);
    return $res->single_sentence('Email/import')->arguments;
  };

  my $first = $import->($mbox_1);
  my $first_id = $first->{created}{new}{id};
  ok($first_id, "first import succeeded") or return diag explain $first;

  my $second = $import->($mbox_2);

  # RFC 8621 S4.8: a server forbidding duplicates "MUST reject attempts to
  # import an Email considered to be a duplicate with an "alreadyExists"
  # SetError" with an "existingId"; otherwise "the newly created Email object
  # MUST have a separate id and independent mutable properties".
  if (my $err = $second->{notCreated}{new}) {
    jcmp_deeply(
      $err,
      superhashof({ type => 'alreadyExists', existingId => $first_id }),
      "duplicate is rejected with alreadyExists naming the existing email",
    ) or diag explain $second;
    return;
  }

  my $second_id = $second->{created}{new}{id};
  ok($second_id, "duplicate was imported") or return diag explain $second;
  isnt($second_id, $first_id, "duplicate has a separate id");

  my $set_res = $tester->request([[
    "Email/set" => {
      update => {
        $second_id => { 'keywords/$flagged' => jtrue },
      },
    },
  ]]);
  ok(
    exists $set_res->single_sentence('Email/set')->arguments->{updated}{$second_id},
    "flagged the duplicate",
  ) or diag explain $set_res->as_stripped_triples;

  $tester->request_ok(
    [ "Email/get" => { ids => [ $first_id, $second_id ], properties => [ qw(keywords mailboxIds) ] } ],
    superhashof({
      list => bag(
        { id => $first_id,  keywords => {}, mailboxIds => { $mbox_1->id => jtrue } },
        { id => $second_id, keywords => { '$flagged' => jtrue }, mailboxIds => { $mbox_2->id => jtrue } },
      ),
    }),
    "the two emails have independent keywords and mailboxIds",
  );
};
