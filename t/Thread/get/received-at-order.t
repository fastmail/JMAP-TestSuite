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

  # Created in an order that differs from receivedAt order.
  my $middle = $mailbox->add_message({
    subject    => "Order test $$",
    receivedAt => '2020-01-01T02:00:00Z',
  });
  my $oldest = $middle->reply({
    subject    => "Re: Order test $$",
    receivedAt => '2020-01-01T01:00:00Z',
  });
  my $newest = $middle->reply({
    subject    => "Re: Order test $$",
    receivedAt => '2020-01-01T03:00:00Z',
  });

  # RFC 8621 S3: the threading algorithm is not mandated.
  unless (1 == keys %{{ map {; $_->threadId => 1 } $middle, $oldest, $newest }}) {
    note("server did not put the replies in one thread");
    return;
  }

  my $res = $tester->request([[
    "Thread/get" => { ids => [ $middle->threadId ] },
  ]]);
  ok($res->is_success, "Thread/get") or diag explain $res->response_payload;

  # RFC 8621 S3: emailIds are "sorted by the "receivedAt" date of the
  # Email, oldest first".
  jcmp_deeply(
    $res->single_sentence("Thread/get")->arguments->{list},
    [ {
      id       => jstr($middle->threadId),
      emailIds => [ map {; jstr($_->id) } $oldest, $middle, $newest ],
    } ],
    "emailIds are in receivedAt order, not creation order",
  ) or diag explain $res->as_stripped_triples;
};
