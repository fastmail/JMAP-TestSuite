use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  # Put our message in two boxes. It should be removed from the first when
  # we destroy the mailbox but exist in the second.
  my $mailbox1 = $account->create_mailbox;
  my $mailbox2 = $account->create_mailbox;

  my $blob = $account->email_blob(generic => {});
  ok($blob->is_success, "our upload succeeded (" . $blob->blobId . ")");

  my $message = $account->add_message_to_mailboxes(
    $mailbox1->id, $mailbox2->id,
  );

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

  my $email = $email_res->single_sentence->arguments->{list}[0];
  ok($email, 'our message still exists');

  jcmp_deeply(
    $email->{mailboxIds},
    { $mailbox2->id => JSON::true },
    'message still exists in second mailbox'
  );
};
