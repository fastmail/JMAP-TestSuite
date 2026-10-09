use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $message = $account->create_mailbox->add_message({ subject => "Thread changes $$" });
  my $reply   = $message->reply({ subject => "Re: Thread changes $$" });

  # RFC 8621 S3: the threading algorithm is not mandated.
  unless ($reply->threadId eq $message->threadId) {
    note("server did not thread the reply with its parent");
    return;
  }

  my $thread_id = $message->threadId;

  # Other tests share this account, so only our thread's place is checked.
  my $changes_since = sub {
    my ($state) = @_;
    my $res = $tester->request([[
      "Thread/changes" => { sinceState => $state },
    ]]);
    ok($res->is_success, "Thread/changes") or diag explain $res->response_payload;
    my $args = $res->single_sentence("Thread/changes")->arguments;
    return {
      map {; my $k = $_; $k => scalar grep {; $_ eq $thread_id } @{ $args->{$k} || [] } }
      qw(created updated destroyed)
    };
  };

  # RFC 8620 S5.2: losing one of two Emails updates the Thread's emailIds;
  # losing the last one leaves no Thread, so it is destroyed.
  my $state = $account->get_state('thread');
  $reply->destroy;
  is_deeply(
    $changes_since->($state),
    { created => 0, updated => 1, destroyed => 0 },
    "destroying one email of two reports the thread updated",
  );

  $state = $account->get_state('thread');
  $message->destroy;
  is_deeply(
    $changes_since->($state),
    { created => 0, updated => 0, destroyed => 1 },
    "destroying the last email reports the thread destroyed",
  );
};
