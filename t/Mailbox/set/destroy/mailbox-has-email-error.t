use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  for my $test (
    [ 'implicit onDestroyRemoveMessages false' => {} ],
    [ 'explicit onDestroyRemoveMessages false' => {
        onDestroyRemoveMessages => JSON::false,
      },
    ],
  ) {
    my ($desc, $arg) = @$test;

    subtest "has message - $desc" => sub {
      my $mailbox1 = $account->create_mailbox;

      my $message = $mailbox1->add_message;

      my $set_res = $tester->request([[
        "Mailbox/set" => {
          destroy => [ $mailbox1->id ],
          %$arg,
        },
      ]]);

      jcmp_deeply(
        $set_res->single_sentence('Mailbox/set')->arguments->{notDestroyed},
        {
          $mailbox1->id => {
            type => 'mailboxHasEmail',
          },
        },
        'got mailboxHasEmail error'
      );

      my $get_res = $tester->request([[
        "Mailbox/get" => { ids => [ $mailbox1->id ] },
      ]]);

      jcmp_deeply(
        $get_res->single_sentence('Mailbox/get')->arguments->{list},
        [superhashof({
          id => $mailbox1->id,
        })],
        'mailbox still exists'
      );

      my $email_res = $tester->request([[
        "Email/get" => { ids => [ $message->id ], },
      ]]);

      my $email = $email_res->single_sentence->arguments->{list}[0];
      ok($email, 'our message still exists');
    };
  }
};
