use jmaptest;

attr pristine  => 1;
attr pool_pairs => 1;

test {
  my ($self) = @_;

  my ($from_account, $to_account) = $self->pool_account_pair;
  my $from_tester = $from_account->tester;

  $from_tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $src_mbox  = $from_account->create_mailbox;
  my $dest_mbox = $to_account->create_mailbox;
  my $msg = $src_mbox->add_message({
    subject    => "copy overrides $$",
    keywords   => { '$seen' => jtrue },
    receivedAt => '2020-01-02T03:04:05Z',
  });

  # RFC 8620 S5.4: "any other properties included are used instead of the
  # current value for that property on the original."
  my $res = $from_tester->request([[
    "Email/copy" => {
      fromAccountId => $from_account->accountId,
      accountId     => $to_account->accountId,
      create => {
        c1 => {
          id         => $msg->id,
          mailboxIds => { $dest_mbox->id => jtrue },
          keywords   => { '$flagged' => jtrue },
          receivedAt => '2019-05-06T07:08:09Z',
        },
      },
    },
  ]]);

  my $new_id = $res->single_sentence('Email/copy')->arguments->{created}{c1}{id};
  ok($new_id, "copied the email") or return diag explain $res->as_stripped_triples;

  $to_account->tester->request_ok(
    [ "Email/get" => { ids => [ $new_id ], properties => [ qw(mailboxIds keywords receivedAt) ] } ],
    superhashof({
      list => [ {
        id         => $new_id,
        mailboxIds => { $dest_mbox->id => jtrue },
        keywords   => { '$flagged' => jtrue },
        receivedAt => '2019-05-06T07:08:09Z',
      } ],
    }),
    "the copy has the given keywords and receivedAt",
  );
};
