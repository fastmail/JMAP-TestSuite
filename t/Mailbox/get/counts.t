use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mailbox = $account->create_mailbox;

  my @emails = (
    $mailbox->add_message,
    $mailbox->add_message({ keywords => { '$seen'    => JSON::true } }),
    $mailbox->add_message({ keywords => { '$draft'   => JSON::true } }),
    $mailbox->add_message({ keywords => { '$flagged' => JSON::true } }),
  );
  push @emails, $emails[0]->reply;

  my $got = $tester->request([[
    "Email/get" => {
      ids        => [ map {; $_->id } @emails ],
      properties => [ 'threadId', 'keywords' ],
    },
  ]])->single_sentence("Email/get")->arguments->{list};

  my %threads = map {; $_->{threadId} => 1 } @$got;
  my @unread  = grep {; !$_->{keywords}{'$seen'} && !$_->{keywords}{'$draft'} } @$got;

  my $mb = $tester->request([[
    "Mailbox/get" => {
      ids        => [ $mailbox->id ],
      properties => [ qw(totalEmails unreadEmails totalThreads unreadThreads) ],
    },
  ]])->single_sentence("Mailbox/get")->arguments->{list}[0];

  # RFC 8621 S2: totalEmails is "The number of Emails in this Mailbox";
  # unreadEmails counts those "that have neither the '$seen' keyword nor the
  # '$draft' keyword"; totalThreads counts Threads with an Email here.
  is($mb->{totalEmails},  scalar @emails, "totalEmails counts every Email");
  is($mb->{unreadEmails}, scalar @unread, "unreadEmails excludes \$seen and \$draft")
    or diag explain $got;
  is($mb->{totalThreads}, scalar keys %threads, "totalThreads counts distinct Threads")
    or diag explain $got;

  # RFC 8621 S2: how unreadThreads is determined "is not mandated", but it
  # counts Threads, so it can't exceed totalThreads.
  ok(
    $mb->{unreadThreads} >= 0 && $mb->{unreadThreads} <= $mb->{totalThreads},
    "unreadThreads is between 0 and totalThreads",
  ) or diag explain $mb;
};
