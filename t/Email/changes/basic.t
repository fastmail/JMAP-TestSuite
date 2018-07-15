use strict;
use warnings;
use Test::Routine;
use Test::Routine::Util;

with 'JMAP::TestSuite::Tester';

use JMAP::TestSuite::Util qw(batch_ok);

use Test::Deep ':v1';
use Test::Deep::JType;
use Test::More;
use JSON qw(decode_json);
use JSON::Typist;
use Test::Abortable;

test "Email/changes with no changes" => sub {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $message = $account->create_mailbox->add_message;

  my $state = $account->get_state('email');

  my $res = $tester->request([[
    "Email/changes" => { sinceState => $state, },
  ]]);
  ok($res->is_success, "Email/changes")
    or diag explain $res->http_response->as_string;

  my $changes = $res->single_sentence("Email/changes")->arguments;

  jcmp_deeply(
    $changes,
    {
      accountId      => jstr($account->accountId),
      oldState       => jstr($state),
      newState       => jstr($state),
      hasMoreChanges => jfalse,
      created        => [],
      updated        => [],
      destroyed      => [],
    },
    "Response looks good",
  ) or diag explain $res->as_stripped_triples;
};

test "Email/changes with changes" => sub {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  subtest "created entities show up in created" => sub {
    my $state = $account->get_state('email');

    my $message = $account->create_mailbox->add_message;

    my $res = $tester->request([[
      "Email/changes" => { sinceState => $state, },
    ]]);
    ok($res->is_success, "Email/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Email/changes")->arguments,
      {
        accountId      => jstr($account->accountId),
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [ $message->id ],
        updated        => [],
        destroyed      => [],
      },
      "Response looks good",
    );
  };

  subtest "updated entities show up in updated" => sub {
    my $message = $account->create_mailbox->add_message;

    my $state = $account->get_state('email');

    $message->update({ keywords => { foo => JSON::true } });

    my $res = $tester->request([[
      "Email/changes" => { sinceState => $state, },
    ]]);
    ok($res->is_success, "Email/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Email/changes")->arguments,
      {
        accountId      => jstr($account->accountId),
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [ $message->id ],
        destroyed      => [],
      },
      "Response looks good",
    );
  };

  subtest "destroyed entities show up in destroyed" => sub {
    my $message = $account->create_mailbox->add_message;

    my $state = $account->get_state('email');

    $message->destroy;

    my $res = $tester->request([[
      "Email/changes" => { sinceState => $state, },
    ]]);
    ok($res->is_success, "Email/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Email/changes")->arguments,
      {
        accountId      => jstr($account->accountId),
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [],
        destroyed      => [ $message->id ],
      },
      "Response looks good",
    );
  };
};

test "maxChanges and hasMoreChanges" => sub {
  my ($self) = @_;

  # XXX - Skip if the server under test doesn't support it

  my $account = $self->any_account;
  my $tester  = $account->tester;

  # Create two message so we should have 3 states (start state,
  # new email 1 state, new email 2 state). Then, ask for changes
  # from start state, with a maxChanges set to 1 so we should get
  # hasMoreChanges when sinceState is start state.

  my $start_state = $account->get_state('email');

  my $message1 = $account->create_mailbox->add_message;

  my $message2 = $account->create_mailbox->add_message;

  my $end_state = $account->get_state('email');

  my $middle_state;

  subtest "changes from start state" => sub {
    my $res = $tester->request([[
      "Email/changes" => {
        sinceState => $start_state,
        maxChanges => 1,
      },
    ]]);
    ok($res->is_success, "Email/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Email/changes")->arguments,
      {
        accountId      => jstr($account->accountId),
        oldState       => jstr($start_state),
        newState       => all(jstr, none($start_state, $end_state)),
        hasMoreChanges => jtrue,
        created        => [ $message1->id ],
        updated        => [],
        destroyed      => [],
      },
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;

    $middle_state = $res->single_sentence->arguments->{newState};
    ok($middle_state, 'grabbed middle state');
  };


  subtest "changes from middle state to final state" => sub {
    my $res = $tester->request([[
      "Email/changes" => {
        sinceState => $middle_state,
        maxChanges => 1,
      },
    ]]);
    ok($res->is_success, "Email/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Email/changes")->arguments,
      {
        accountId      => jstr($account->accountId),
        oldState       => jstr($middle_state),
        newState       => jstr($end_state),
        hasMoreChanges => jfalse,
        created        => [ $message2->id ],
        updated        => [],
        destroyed      => [],
      },
      "Response looks good",
    );
  };

  subtest "final state says no changes" => sub {
    my $res = $tester->request([[
      "Email/changes" => {
        sinceState => $end_state,
        maxChanges => 1,
      },
    ]]);
    ok($res->is_success, "Email/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Email/changes")->arguments,
      {
        accountId      => jstr($account->accountId),
        oldState       => jstr($end_state),
        newState       => jstr($end_state),
        hasMoreChanges => jfalse,
        created        => [],
        updated        => [],
        destroyed      => [],
      },
      "Response looks good",
    );
  };
};

run_me;
done_testing;
