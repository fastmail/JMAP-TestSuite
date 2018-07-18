use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mailbox1 = $account->create_mailbox;

  my $blob = $account->email_blob(generic => {});
  ok($blob->is_success, "our upload succeeded (" . $blob->blobId . ")");

  my $message = $mailbox1->add_message;

  my $set_res = $tester->request([[
    "Mailbox/set" => {
      destroy => [ $mailbox1->id ],
      onDestroyRemoveMessages => JSON::true,
    },
  ]]);

  jcmp_deeply(
    $set_res->single_sentence('Mailbox/set')->arguments->{destroyed},
    [ $mailbox1->id ],
    'mailbox destroyed'
  );

  my $get_res = $tester->request([[
    "Mailbox/get" => { ids => [ $mailbox1->id ] },
  ]]);

  jcmp_deeply(
    $get_res->single_sentence('Mailbox/get')->arguments->{notFound},
    [ $mailbox1->id ],
    'our destroyed mailbox not found'
  );

  my $email_res = $tester->request([[
    "Email/get" => { ids => [ $message->id ], },
  ]]);

  jcmp_deeply(
    $email_res->single_sentence('Email/get')->arguments->{notFound},
    [ $message->id ],
    'our destroyed email not found'
  );
};
