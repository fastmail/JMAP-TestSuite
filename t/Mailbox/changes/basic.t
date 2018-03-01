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

test "Mailbox/changes with no changes" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $mailbox = $self->context->create_mailbox({
    name => "A new mailbox",
  });

  my $state = $self->context->get_state('mailbox');

  my $res = $tester->request({
    using => [ "ietf:jmapmail" ],
    methodCalls => [[
      "Mailbox/changes" => { sinceState => $state, },
    ]],
  });
  ok($res->is_success, "Mailbox/changes")
    or diag explain $res->http_response->as_string;

  jcmp_deeply(
    $res->single_sentence("Mailbox/changes")->arguments,
    superhashof({
      accountId      => jstr($self->context->accountId),
      oldState       => jstr($state),
      newState       => jstr($state),
      hasMoreChanges => jfalse,
      changed        => undef,
      destroyed      => undef,
    }),
    "Response looks good",
  );
};

test "Mailbox/changes with changes" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  subtest "created entities show up in changed" => sub {
    my $state = $self->context->get_state('mailbox');

    my $mailbox = $self->context->create_mailbox({
      name => "A new mailbox",
    });

    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/changes" => { sinceState => $state, },
      ]],
    });
    ok($res->is_success, "Mailbox/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/changes")->arguments,
      superhashof({
        accountId      => jstr($self->context->accountId),
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        changed        => [ $mailbox->id ],
        destroyed      => undef,
      }),
      "Response looks good",
    );
  };

  subtest "updated entities show up in changed" => sub {
    my $mailbox = $self->context->create_mailbox({
      name => "A new mailbox",
    });

    my $state = $self->context->get_state('mailbox');

    subtest "update the mailbox" => sub {
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Mailbox/set" => {
            update => {
              $mailbox->id => { name => "An updated mailbox" },
            },
          },
        ]],
      });
      ok($res->is_success, "Mailbox/set")
        or diag explain $res->http_response->as_string;
    };

    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/changes" => { sinceState => $state, },
      ]],
    });
    ok($res->is_success, "Mailbox/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/changes")->arguments,
      superhashof({
        accountId      => jstr($self->context->accountId),
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        changed        => [ $mailbox->id ],
        destroyed      => undef,
      }),
      "Response looks good",
    );
  };

  subtest "destroyed entities show up in destroyed" => sub {
    my $mailbox = $self->context->create_mailbox({
      name => "A new mailbox",
    });

    my $state = $self->context->get_state('mailbox');

    subtest "destroy the mailbox" => sub {
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Mailbox/set" => {
            destroy => [ $mailbox->id ],
          },
        ]],
      });
      ok($res->is_success, "Mailbox/set")
        or diag explain $res->http_response->as_string;
    };

    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/changes" => { sinceState => $state, },
      ]],
    });
    ok($res->is_success, "Mailbox/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/changes")->arguments,
      superhashof({
        accountId      => jstr($self->context->accountId),
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        changed        => undef,
        destroyed      => [ $mailbox->id ],
      }),
      "Response looks good",
    );
  };
};

test "maxChanges and hasMoreChanges" => sub {
  my ($self) = @_;

  # XXX - Skip if the server under test doesn't support it

  my $tester = $self->tester;

  # Create two mailboxes so we should have 3 states (start state,
  # new mailbox 1 state, new mailbox 2 state). Then, ask for changes
  # from start state, with a maxChanges set to 1 so we should get
  # hasMoreChanges when sinceState is start state.

  my $start_state = $self->context->get_state('mailbox');

  my $mailbox1 = $self->context->create_mailbox({
    name => "A new mailbox",
  });

  my $mailbox2 = $self->context->create_mailbox({
    name => "A second new mailbox",
  });

  my $end_state = $self->context->get_state('mailbox');

  my $middle_state;

  subtest "changes from start state" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/changes" => {
          sinceState => $start_state,
          maxChanges => 1,
        },
      ]],
    });
    ok($res->is_success, "Mailbox/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/changes")->arguments,
      superhashof({
        accountId      => jstr($self->context->accountId),
        oldState       => jstr($start_state),
        newState       => all(jstr, none($start_state, $end_state)),
        hasMoreChanges => jtrue,
        changed        => [ $mailbox1->id ],
        destroyed      => undef,
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;

    $middle_state = $res->single_sentence->arguments->{newState};
    ok($middle_state, 'grabbed middle state');
  };


  subtest "changes from middle state to final state" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/changes" => {
          sinceState => $middle_state,
          maxChanges => 1,
        },
      ]],
    });
    ok($res->is_success, "Mailbox/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/changes")->arguments,
      superhashof({
        accountId      => jstr($self->context->accountId),
        oldState       => jstr($middle_state),
        newState       => jstr($end_state),
        hasMoreChanges => jfalse,
        changed        => [ $mailbox2->id ],
        destroyed      => undef,
      }),
      "Response looks good",
    );
  };

  subtest "final state says no changes" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/changes" => {
          sinceState => $end_state,
          maxChanges => 1,
        },
      ]],
    });
    ok($res->is_success, "Mailbox/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/changes")->arguments,
      superhashof({
        accountId      => jstr($self->context->accountId),
        oldState       => jstr($end_state),
        newState       => jstr($end_state),
        hasMoreChanges => jfalse,
        changed        => undef,
        destroyed      => undef,
      }),
      "Response looks good",
    );
  };
};

run_me;
done_testing;
