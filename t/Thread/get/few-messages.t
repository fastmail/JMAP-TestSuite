use jmaptest;

use JMAP::TestSuite::Util qw(thread);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mailbox1 = $account->create_mailbox;

  # RFC 8621 S3: emailIds are "sorted by the receivedAt date", oldest first.
  my $message1 = $mailbox1->add_message({
    subject    => 'Thread test',
    receivedAt => '2020-01-01T00:00:00Z',
  });
  my $message2 = $message1->reply({
    subject    => 'Re: Thread test',
    receivedAt => '2020-01-01T01:00:00Z',
  });

  my $other = $mailbox1->add_message({ subject => 'Unrelated' });

  is($message1->threadId, $message2->threadId, 'threadIds match');
  isnt($other->threadId, $message1->threadId, 'other message not in thread');

  my $get_res = $tester->request([[
    "Thread/get" => { ids => [ $message1->threadId ] },
  ]]);

  jcmp_deeply(
    $get_res->sentence_named('Thread/get')->arguments,
    {
      accountId => jstr($account->accountId),
      state => jstr(),
      list => [
        thread({
          id       => jstr($message1->threadId),
          emailIds => [ jstr($message1->id), jstr($message2->id) ],
        }),
      ],
      notFound => [],
    },
    "Thread/get only returns messages in that thread, sorted properly",
  ) or diag explain $get_res->as_stripped_triples;
};
