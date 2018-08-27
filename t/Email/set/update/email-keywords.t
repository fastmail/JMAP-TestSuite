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
    [ "Email/get" => { ids => [ $message->id ] } ],
    superhashof({ list => [ superhashof({ keywords => {} }) ] }),
    "newly created email has no keywords",
  );

  $tester->request_ok(
    [
      "Email/set" => {
        update => {
          $message->id => { keywords => { '$Flagged' => jtrue() } }
        },
      }
    ],
    superhashof({ updated => { $message->id => ignore } }),
    'we set $flagged keyword',
  );

  $tester->request_ok(
    [ "Email/get" => { ids => [ $message->id ] } ],
    superhashof({ list => [ superhashof({ keywords => { '$flagged' => jtrue() } }) ] }),
    "...and it worked, keyword lowercased",
  );
};
