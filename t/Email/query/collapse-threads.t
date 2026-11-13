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

  my $first = $mailbox->add_message({
    subject    => "collapse $$",
    receivedAt => '2020-01-01T00:00:01Z',
  });
  my $single = $mailbox->add_message({
    subject    => "alone $$",
    receivedAt => '2020-01-01T00:00:02Z',
  });
  my $reply = $first->reply({
    subject    => "Re: collapse $$",
    receivedAt => '2020-01-01T00:00:03Z',
  });

  # RFC 8621 S3: the threading algorithm is not mandated.
  unless ($reply->threadId eq $first->threadId) {
    note("server did not thread the reply with its parent; nothing to collapse");
    return;
  }

  # RFC 8621 S4.4.3: a Thread appears "only *once* in the result, at the
  # position of the first Email in the list that belongs to the Thread".
  for my $test (
    [ jtrue(),  'oldest first', [ $first, $single ] ],
    [ jfalse(), 'newest first', [ $reply, $single ] ],
  ) {
    my ($asc, $desc, $want) = @$test;

    my $res = $tester->request([[
      "Email/query" => {
        filter          => { inMailbox => $mailbox->id },
        sort            => [ { property => 'receivedAt', isAscending => $asc } ],
        collapseThreads => jtrue(),
        calculateTotal  => jtrue(),
      },
    ]]);
    ok($res->is_success, "Email/query $desc")
      or diag explain $res->response_payload;

    my $args = $res->single_sentence("Email/query")->arguments;
    jcmp_deeply(
      [ $args->{ids}, $args->{total} ],
      [ [ map {; jstr($_->id) } @$want ], jnum(2) ],
      "$desc: one email per thread, and total counts the collapsed list",
    ) or diag explain $res->as_stripped_triples;
  }
};
