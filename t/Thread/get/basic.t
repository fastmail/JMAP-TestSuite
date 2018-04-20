use strict;
use warnings;
use Test::Routine;
use Test::Routine::Util;

with 'JMAP::TestSuite::Tester';

use JMAP::TestSuite::Util qw(batch_ok pristine_test);

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

  my $tester = $self->tester;
  my $context = $self->context;

  my $mailbox1 = $self->context->create_mailbox;

  my $message1 = $mailbox1->add_message;
  my $message2 = $message1->reply;

  my $other = $mailbox1->add_message;

  is($message1->threadId, $message2->threadId, 'threadIds match');
  isnt($other->threadId, $message1->threadId, 'other message not in thread');

  my $get_res = $tester->request({
    using => [ "ietf:jmapmail" ],
    methodCalls => [[
      "Thread/get" => { ids => [ $message1->threadId ] },
    ]],
  });

  jcmp_deeply(
    $get_res->sentence_named('Thread/get')->arguments,
    {
      accountId => jstr($self->context->accountId),
      state => jstr(),
      list => [
        {
          id => jstr($message1->threadId),
          emailIds => [ jstr($message1->id), jstr($message2->id) ],
        },
      ],
      notFound => undef,
    },
    "Thread/get only returns messages in that thread, sorted properly",
  );
};

pristine_test "Unknown ids gives fills in notFound" => sub {
  my ($self) = @_;

  my $tester = $self->tester;
  my $context = $self->context;

  my $other_context = $self->server->pristine_account->context;
  my $other_mailbox = $other_context->create_mailbox;
  my $other_message = $other_mailbox->add_message;

  # Thread is in another account so we shouldn't see it, therefore
  # notFound!
  my $get_res = $tester->request({
    using => [ "ietf:jmapmail" ],
    methodCalls => [[
      "Thread/get" => { ids => [ $other_message->threadId ] },
    ]],
  });

  jcmp_deeply(
    $get_res->sentence_named('Thread/get')->arguments,
    {
      accountId => jstr($self->context->accountId),
      state => jstr(),
      list => [],
      notFound => [ jstr($other_message->threadId) ],
    },
    "Thread/get fills in notFound for messages in another account",
  );
};

test "empty list" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $get_res = $tester->request({
    using => [ "ietf:jmapmail" ],
    methodCalls => [[
      "Thread/get" => { ids => [ ] },
    ]],
  });

  jcmp_deeply(
    $get_res->sentence_named('Thread/get')->arguments,
    {
      accountId => jstr($self->context->accountId),
      state => jstr(),
      list => [],
      notFound => undef,
    },
    "Thread/get with empty ids list returns good response",
  );
};

run_me;
done_testing;

