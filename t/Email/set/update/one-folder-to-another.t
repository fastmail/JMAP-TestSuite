use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  for my $mover (
    {
      desc => "double patch",
      code => sub {
        my ($m1, $m2) = @_;
        my $i1 = $m1->id;
        my $i2 = $m2->id;
        return { "mailboxIds/$i1" => undef, "mailboxIds/$i2" => jtrue };
      }
    },
    {
      desc => "replace mailboxIds property",
      code => sub {
        my ($m1, $m2) = @_;
        my $i1 = $m1->id;
        my $i2 = $m2->id;
        return { mailboxIds => { $i2 => jtrue } };
      }
    }
  ) {
    subtest "move mail with $mover->{desc}" => sub {
      my $mbox_1 = $account->create_mailbox;
      my $mbox_2 = $account->create_mailbox;

      my $from    = "test$$\@example.net";
      my $to      = "recip$$\@example.net";
      my $subject = "A subject for $$";

      my $message = $mbox_1->add_message({
        from    => $from,
        to      => $to,
        subject => $subject,
      });

      $tester->request_ok(
        [ "Email/get" => { ids => [ $message->id ] } ],
        superhashof({ list => [ superhashof({ mailboxIds => { $mbox_1->id => jtrue } }) ] }),
        "created an email in an existing folder",
      );

      $tester->request_ok(
        [ 'Mailbox/get', { ids => [ $mbox_1->id ] } ],
        superhashof({ list => [ superhashof({ totalEmails => 1, id => $mbox_1->id }) ] }),
        "mailbox 1 totalEmails count is now 1",
      );

      $tester->request_ok(
        [ 'Mailbox/get', { ids => [ $mbox_2->id ] } ],
        superhashof({ list => [ superhashof({ totalEmails => 0, id => $mbox_2->id }) ] }),
        "mailbox 2 totalEmails count is now 0",
      );

      $tester->request_ok(
        [ "Email/set" => { update => { $message->id => $mover->{code}->($mbox_1, $mbox_2) } } ],
        superhashof({ updated => { $message->id => ignore } }),
        "move the email to another mailbox",
      );

      $tester->request_ok(
        [ 'Mailbox/get', { ids => [ $mbox_1->id ] } ],
        superhashof({ list => [ superhashof({ totalEmails => 0, id => $mbox_1->id }) ] }),
        "mailbox 1 totalEmails count is now 0",
      );

      $tester->request_ok(
        [ 'Mailbox/get', { ids => [ $mbox_2->id ] } ],
        superhashof({ list => [ superhashof({ totalEmails => 1, id => $mbox_2->id }) ] }),
        "mailbox 2 totalEmails count is now 1",
      );

      $tester->request_ok(
        [ "Email/get" => { ids => [ $message->id ] } ],
        superhashof({ list => [ superhashof({ mailboxIds => { $mbox_2->id => jtrue } }) ] }),
        "re-gotten message has been moved",
      );
    };
  }
};
