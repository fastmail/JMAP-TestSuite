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
use Test::Abortable;

pristine_test "Thread/changes with no changes" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $message = $self->context->create_mailbox->add_message;

  my $state = $self->context->get_state('thread');

  my $res = $tester->request({
    using => [ "ietf:jmapmail" ],
    methodCalls => [[
      "Thread/changes" => { sinceState => $state, },
    ]],
  });
  ok($res->is_success, "Thread/changes")
    or diag explain $res->http_response->as_string;

  my $changes = $res->single_sentence("Thread/changes")->arguments;

  jcmp_deeply(
    $changes,
    {
      accountId      => jstr($self->context->accountId),
      oldState       => jstr($state),
      newState       => jstr($state),
      hasMoreChanges => jfalse,
      changed        => [],
      destroyed      => [],
    },
    "Response looks good",
  ) or diag explain $res->as_stripped_triples;
};

pristine_test "Thread/changes with changes" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  subtest "created entities show up in changed" => sub {
    my $state = $self->context->get_state('thread');

    my $message = $self->context->create_mailbox->add_message;

    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Thread/changes" => { sinceState => $state, },
      ]],
    });
    ok($res->is_success, "Thread/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Thread/changes")->arguments,
      {
        accountId      => jstr($self->context->accountId),
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        changed        => [ $message->threadId ],
        destroyed      => [],
      },
      "Response looks good",
    );
  };

  subtest "updated entities show up in changed" => sub {
    my $message = $self->context->create_mailbox->add_message;

    my $state = $self->context->get_state('thread');

    $message->reply;

    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Thread/changes" => { sinceState => $state, },
      ]],
    });
    ok($res->is_success, "Thread/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Thread/changes")->arguments,
      {
        accountId      => jstr($self->context->accountId),
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        changed        => [ $message->threadId ],
        destroyed      => [],
      },
      "Response looks good",
    );
  };

  subtest "destroyed entities show up in destroyed" => sub {
    my $message = $self->context->create_mailbox->add_message;

    my $state = $self->context->get_state('thread');

    $message->destroy;

    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Thread/changes" => { sinceState => $state, },
      ]],
    });
    ok($res->is_success, "Thread/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Thread/changes")->arguments,
      {
        accountId      => jstr($self->context->accountId),
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        changed        => [],
        destroyed      => [ $message->threadId ],
      },
      "Response looks good",
    );
  };
};

pristine_test "maxChanges and hasMoreChanges" => sub {
  my ($self) = @_;

  # XXX - Skip if the server under test doesn't support it

  my $tester = $self->tester;

  # Create two message so we should have 3 states (start state,
  # new thread 1 state, new thread 2 state). Then, ask for changes
  # from start state, with a maxChanges set to 1 so we should get
  # hasMoreChanges when sinceState is start state.

  my $start_state = $self->context->get_state('thread');

  my $message1 = $self->context->create_mailbox->add_message;

  my $message2 = $self->context->create_mailbox->add_message;

  my $end_state = $self->context->get_state('thread');

  my $middle_state;

  subtest "changes from start state" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Thread/changes" => {
          sinceState => $start_state,
          maxChanges => 1,
        },
      ]],
    });
    ok($res->is_success, "Thread/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Thread/changes")->arguments,
      {
        accountId      => jstr($self->context->accountId),
        oldState       => jstr($start_state),
        newState       => all(jstr, none($start_state, $end_state)),
        hasMoreChanges => jtrue,
        changed        => [ $message1->threadId ],
        destroyed      => [],
      },
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;

    $middle_state = $res->single_sentence->arguments->{newState};
    ok($middle_state, 'grabbed middle state');
  };


  subtest "changes from middle state to final state" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Thread/changes" => {
          sinceState => $middle_state,
          maxChanges => 1,
        },
      ]],
    });
    ok($res->is_success, "Thread/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Thread/changes")->arguments,
      {
        accountId      => jstr($self->context->accountId),
        oldState       => jstr($middle_state),
        newState       => jstr($end_state),
        hasMoreChanges => jfalse,
        changed        => [ $message2->threadId ],
        destroyed      => [],
      },
      "Response looks good",
    );
  };

  subtest "final state says no changes" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Thread/changes" => {
          sinceState => $end_state,
          maxChanges => 1,
        },
      ]],
    });
    ok($res->is_success, "Thread/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Thread/changes")->arguments,
      {
        accountId      => jstr($self->context->accountId),
        oldState       => jstr($end_state),
        newState       => jstr($end_state),
        hasMoreChanges => jfalse,
        changed        => [],
        destroyed      => [],
      },
      "Response looks good",
    );
  };
};

run_me;
done_testing;
