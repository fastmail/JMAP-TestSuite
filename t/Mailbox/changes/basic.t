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
      newState       => jstr($state),
      oldState       => jstr($state),
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
        newState       => none(jstr($state)),
        oldState       => jstr($state),
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
        newState       => none(jstr($state)),
        oldState       => jstr($state),
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
        newState       => none(jstr($state)),
        oldState       => jstr($state),
        hasMoreChanges => jfalse,
        changed        => undef,
        destroyed      => [ $mailbox->id ],
      }),
      "Response looks good",
    );
  };
};

run_me;
done_testing;
