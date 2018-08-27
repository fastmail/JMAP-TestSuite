use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mailbox1 = $account->create_mailbox;
  my $mailbox2 = $account->create_mailbox({
    parentId => $mailbox1->id,
  });

  subtest "has child" => sub {
    my $set_res = $tester->request([[
      "Mailbox/set" => {
        destroy => [ $mailbox1->id ],
        onDestroyRemoveMessages => JSON::true,
      },
    ]]);

    jcmp_deeply(
      $set_res->single_sentence('Mailbox/set')->arguments->{notDestroyed},
      {
        $mailbox1->id => {
          type => 'mailboxHasChild',
        },
      },
      'got mailboxHasChild error'
    );
  };

  subtest "no longer has child" => sub {
    $mailbox2->destroy;

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
      $get_res->single_sentence('Mailbox/get')->arguments->{list},
      [],
      'no mailboxes returned'
    );

    jcmp_deeply(
      $get_res->single_sentence('Mailbox/get')->arguments->{notFound},
      [ $mailbox1->id ],
      'our destroyed mailbox not found'
    );
  };
};
