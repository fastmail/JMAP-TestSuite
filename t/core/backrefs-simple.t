use strict;
use warnings;
use Test::Routine;
use Test::Routine::Util;

with 'JMAP::TestSuite::Tester';

use JMAP::TestSuite::Util qw(batch_ok pristine_test);

use Test::Deep ':v1';
use Test::Deep::JType;
use Test::More;
use Test::Abortable;

pristine_test "simple backref support" => sub {
  my ($self) = @_;

  my $context = $self->context;
  my $tester = $context->tester;

  my $mailbox1 = $context->create_mailbox;

  my $state = $context->get_state('mailbox');

  my $mailbox2 = $context->create_mailbox;

  subtest "good ref" => sub {
    # Should only see mailbox2
    my $res = $tester->request({
      using => ["ietf:jmapmail"],
      methodCalls => [
        [
          "Mailbox/changes" => {
            sinceState => $state,
          }, "t0",
        ], [
          "Mailbox/get" => {
            "#ids" => {
              resultOf => "t0",
              name     => "Mailbox/changes",
              path     => "/created",
            },
          }, "t1",
        ],
      ],
    });

    my $changes = $res->sentence(0);
    my $get = $res->sentence(1);

    jcmp_deeply(
      $changes->arguments,
      superhashof({
        created => [ $mailbox2->id ],
      }),
      'Mailbox/changes looks good',
    ) or diag explain $res->as_stripped_triples;

    jcmp_deeply(
      $get->arguments,
      superhashof({
        list => [
          superhashof({
            id   => $mailbox2->id,
            name => $mailbox2->name,
          }),
        ],
        notFound => [],
      }),
      'Mailbox/get with backref looks good'
    );
  };

  subtest "bad ref -> resultReference error" => sub {
    for my $test (
      { resultOf => "bad", name => "Mailbox/changes", path => "/created" },
      { resultOf => "t0",  name => "bad",             path => "/created" },
      { resultOf => "t0",  name => "Mailbox/changes", path => "bad"      },
    ) {
      # Should only see mailbox2
      my $res = $tester->request({
        using => ["ietf:jmapmail"],
        methodCalls => [
          [
            "Mailbox/changes" => {
              sinceState => $state,
            }, "t0",
          ], [
            "Mailbox/get" => {
              "#ids" => $test,
            }, "t1"
          ],
        ],
      });

      my $changes = $res->sentence(0);
      my $get = $res->sentence(1);

      jcmp_deeply(
        $changes->arguments,
        superhashof({
          created => [ $mailbox2->id ],
        }),
        'Mailbox/changes looks good',
      );

      jcmp_deeply(
        $get->arguments,
        superhashof({
          type => 'resultReference',
        }),
        'Mailbox/get with bad backref gets error'
      );
    }
  };

  subtest "#foo and foo -> invalidArguments" => sub {
    # Should only see mailbox2
    my $res = $tester->request({
      using => ["ietf:jmapmail"],
      methodCalls => [
        [
          "Mailbox/changes" => {
            sinceState => $state,
          }, "t0",
        ], [
          "Mailbox/get" => {
            ids => [ $mailbox1->id ],
            "#ids" => {
              resultOf => "t0",
              name     => "Mailbox/changes",
              path     => "/created",
            },
          }, "t1",
        ],
      ],
    });

    my $changes = $res->sentence(0);
    my $get = $res->sentence(1);

    jcmp_deeply(
      $changes->arguments,
      superhashof({
        created => [ $mailbox2->id ],
      }),
      'Mailbox/changes looks good',
    );

    TODO: {
      local $TODO = "https://github.com/cyrusimap/cyrus-imapd/issues/2328"
        if $self->server->isa('JMAP::TestSuite::ServerAdapter::Cyrus');

      jcmp_deeply(
        $get->arguments,
        superhashof({
          type => 'invalidArguments',
        }),
        'Mailbox/get with backref and arg sharing name fails'
      ) or diag explain $res->as_stripped_triples;
    };
  };
};

run_me;
done_testing;

