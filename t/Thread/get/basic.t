use strict;
use warnings;
use Test::Routine;
use Test::Routine::Util;

with 'JMAP::TestSuite::Tester';

use JMAP::TestSuite::Util qw(batch_ok thread);

use Test::Deep ':v1';
use Test::Deep::JType;
use Test::More;
use JSON qw(decode_json);
use JSON::Typist;
use Data::GUID qw(guid_string);
use Test::Abortable;

# XXX no ids - server can decide to respond or claim responseToLarge ...

test "Thread/get with a few messages" => sub {
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

# We use ->pristine_account directly so we must support pristine
test "Unknown ids goes in notFound" => { required_pristine => 1 } => sub {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $other_account = $self->pristine_account;
  my $other_mailbox = $other_account->create_mailbox;
  my $other_message = $other_mailbox->add_message;

  # Thread is in another account so we shouldn't see it, therefore
  # notFound!
  my $get_res = $tester->request([[
    "Thread/get" => { ids => [ $other_message->threadId ] },
  ]]);

  jcmp_deeply(
    $get_res->sentence_named('Thread/get')->arguments,
    {
      accountId => jstr($account->accountId),
      state => jstr(),
      list => [],
      notFound => [ jstr($other_message->threadId) ],
    },
    "Thread/get fills in notFound for messages in another account",
  );
};

test "empty list" => sub {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $get_res = $tester->request([[
    "Thread/get" => { ids => [ ] },
  ]]);

  jcmp_deeply(
    $get_res->sentence_named('Thread/get')->arguments,
    {
      accountId => jstr($account->accountId),
      state => jstr(),
      list => [],
      notFound => [],
    },
    "Thread/get with empty ids list returns good response",
  );
};

run_me;
done_testing;

