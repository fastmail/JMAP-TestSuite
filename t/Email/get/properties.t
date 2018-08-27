use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;

  my $from    = "test$$\@example.net";
  my $to      = "recip$$\@example.net";
  my $subject = "A subject for $$";

  my $message = $mbox->add_message;
  my $reply = $message->reply({
    from    => $from,
    to      => $to,
    subject => $subject,
    headers => [
      Sender     => "sender$from",
      CC         => "cc$from",
      BCC        => "bcc$from",
      'Reply-To' => "rt$from",
    ],
  });

  my $em_msg_id = $message->messageId->[0];
  my $reply_msg_id = $reply->messageId->[0];

  my $empty = any([], undef);

  subtest "no properties specified, defaults returned" => sub {
    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $reply->id ],
      },
    ]]);
    ok($res->is_success, "Email/get")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Email/get")->arguments,
      superhashof({
        accountId => jstr($account->accountId),
        state     => jstr(),
        list      => [{
          id            => $reply->id,
          blobId        => jstr(),
          threadId      => jstr(),
          mailboxIds    => {
            $mbox->id . "" => jtrue(),
          },
          keywords      => superhashof({}),
          size          => jnum(),
          receivedAt    => re('\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\dZ'),
          messageId     => [ $reply_msg_id ],
          inReplyTo     => [ $em_msg_id ],
          references    => [ $em_msg_id ],
          sender        => [{ name => undef, email => "sender$from" }],
          from          => [{ name => undef, email => $from }],
          to            => [{ name => undef, email => $to }],
          cc            => [{ name => undef, email => "cc$from" }],
          bcc           => [{ name => undef, email => "bcc$from" }],
          replyTo       => [{ name => undef, email => "rt$from" }],
          subject       => $subject,
          sentAt        => re('\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\dZ'),
          hasAttachment => jfalse(),
          preview       => jstr(),
          bodyValues    => {},
          textBody => [
            superhashof({ partId => jstr() }),
          ],
          htmlBody => [
            superhashof({ partId => jstr() }),
          ],
          attachments  => $empty,
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "limit to no properties" => sub {
    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $reply->id ],
        properties => [],
      },
    ]]);
    ok($res->is_success, "Email/get")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Email/get")->arguments,
      superhashof({
        accountId => jstr($account->accountId),
        state     => jstr(),
        list      => [{
          id => $reply->id,
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "limit to all properties" => sub {
    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $reply->id ],
        properties => [qw(
          id blobId threadId mailboxIds keywords size
          receivedAt messageId inReplyTo references sender from
          to cc bcc replyTo subject sentAt hasAttachment
          preview bodyValues textBody htmlBody attachments
          headers bodyStructure
        )],
      },
    ]]);
    ok($res->is_success, "Email/get")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Email/get")->arguments,
      superhashof({
        accountId => jstr($account->accountId),
        state     => jstr(),
        list      => [{
          id            => $reply->id,
          blobId        => jstr(),
          threadId      => jstr(),
          mailboxIds    => {
            $mbox->id . "" => jtrue(),
          },
          keywords      => superhashof({}),
          size          => jnum(),
          receivedAt    => re('\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\dZ'),
          messageId     => [ $reply_msg_id ],
          inReplyTo     => [ $em_msg_id ],
          references    => [ $em_msg_id ],
          sender        => [{ name => undef, email => "sender$from" }],
          from          => [{ name => undef, email => $from }],
          to            => [{ name => undef, email => $to }],
          cc            => [{ name => undef, email => "cc$from" }],
          bcc           => [{ name => undef, email => "bcc$from" }],
          replyTo       => [{ name => undef, email => "rt$from" }],
          subject       => $subject,
          sentAt        => re('\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\dZ'),
          hasAttachment => jfalse(),
          preview       => jstr(),
          bodyValues    => {},
          textBody => [
            superhashof({ partId => jstr() }),
          ],
          htmlBody => [
            superhashof({ partId => jstr() }),
          ],
          attachments  => $empty,
          headers => [
            {
              name  => 'From',
              value => re(qr/\Q$from\E/),
            }, {
              name  => 'To',
              value => re(qr/\Q$to\E/),
            }, {
              name  => 'Subject',
              value => re(qr/\Q$subject\E/),
            }, {
              name  => 'Message-Id',
              value => re(qr/<.*>/),
            }, {
              name  => 'Sender',
              value => re(qr/\w/),
            }, {
              name  => 'CC',
              value => re(qr/\w/),
            }, {
              name  => 'BCC',
              value => re(qr/\w/),
            }, {
              name  => 'Reply-To',
              value => re(qr/\w/),
            }, {
              name  => 'In-Reply-To',
              value => re(qr/\w/),
            }, {
              name  => 'References',
              value => re(qr/\w/),
            }, {
              name  => 'Date',
              value => re(qr/\w/),
            }, {
              name  => 'MIME-Version',
              value => re(qr/1\.0/),
            },
          ],
          bodyStructure => superhashof({
            partId => jstr(),
          }),
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "limit to some properties" => sub {
    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $reply->id ],
        properties => [qw(
          threadId size preview
        )],
      },
    ]]);
    ok($res->is_success, "Email/get")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Email/get")->arguments,
      superhashof({
        accountId => jstr($account->accountId),
        state     => jstr(),
        list      => [{
          id       => $reply->id,
          threadId => jstr(),
          size     => jnum(),
          preview  => jstr(),
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };
};
