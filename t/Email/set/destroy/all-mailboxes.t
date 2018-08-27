use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;

  my $from    = "test$$\@example.net";
  my $to      = "recip$$\@example.net";
  my $subject = "A subject for $$";

  my $message = $mbox->add_message({
    from    => $from,
    to      => $to,
    subject => $subject,
  });

  $tester->request_ok(
    [
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [ 'mailboxIds' ],
      },
    ],
    superhashof({
      list => [
        { id => $message->id, mailboxIds => { $mbox->id => jtrue } },
      ],
    }),
    "we made a message and it's in a mailbox",
  );

  $tester->request_ok(
    [ 'Mailbox/get', { ids => [ $mbox->id ] } ],
    superhashof({ list => [ superhashof({ totalEmails => 1, id => $mbox->id }) ] }),
    "totalEmails count is now 1",
  );

  $tester->request_ok(
    [ 'Email/set', { destroy => [ $message->id ] } ],
    superhashof({ destroyed => [ $message->id ] }),
    "we destroyed an email",
  );

  $tester->request_ok(
    [ 'Email/get', { ids => [ $message->id ] } ],
    superhashof({
      list     => [],
      notFound => [ $message->id ],
    }),
    "Email no longer found"
  );

  $tester->request_ok(
    [ 'Mailbox/get', { ids => [ $mbox->id ] } ],
    superhashof({ list => [ superhashof({ totalEmails => 0, id => $mbox->id }) ] }),
    "totalEmails count is now 0",
  );
};
