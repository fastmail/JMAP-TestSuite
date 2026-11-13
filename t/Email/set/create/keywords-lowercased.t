use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mbox = $account->create_mailbox;

  my $res = $tester->request([[
    "Email/set" => {
      create => {
        new => {
          mailboxIds => { $mbox->id => jtrue },
          keywords   => { '$Seen' => jtrue, 'MixedCase' => jtrue },
          subject    => "keywords lowercased $$",
        },
      },
    },
  ]]);

  my $id = $res->single_sentence('Email/set')->arguments->{created}{new}{id};
  ok($id, "created an email") or return diag explain $res->as_stripped_triples;

  # RFC 8621 S4.1.1: "Because JSON is case sensitive, servers MUST return
  # keywords in lowercase."
  $tester->request_ok(
    [ "Email/get" => { ids => [ $id ], properties => [ 'keywords' ] } ],
    superhashof({
      list => [ { id => $id, keywords => { '$seen' => jtrue, 'mixedcase' => jtrue } } ],
    }),
    "keywords come back lowercased",
  );
};
