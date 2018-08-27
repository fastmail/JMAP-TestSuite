use jmaptest;

use JMAP::TestSuite::Util qw(thread);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mailbox1 = $account->create_mailbox;

  my $message1 = $mailbox1->add_message;
  my $message2 = $message1->reply;

  my $other = $mailbox1->add_message;

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
