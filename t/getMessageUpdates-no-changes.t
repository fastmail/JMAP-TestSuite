use strict;
use warnings;

use JMAP::TestSuite;
use Test::Deep::JType 0.004;
use Test::More;

my $server = JMAP::TestSuite->get_server;

$server->simple_test(sub {
  my ($context) = @_;

  # If getMessageUpdates returns no updates, we should get 0 records back
  # with fetchRecords, not an error. The basic problem is that getMessages
  # expects ids to have at least one value.

  # Get state
  my $res = $context->tester->request([
    [
      getMessageList => {  },
    ],
  ]);
  ok($res->is_success, 'called getMessageList');

  my $state = $res->sentence(0)->arguments->{state};
  ok(defined $state, "got state: $state")
    or diag explain $res->as_stripped_struct;

  $res = $context->tester->request([
    [
      getMessageUpdates => {
        sinceState   => $state,
        fetchRecords => \1,
      },
    ]
  ]);

  ok($res->is_success, 'called getMessageUpdates')
    or diag explain $res->http_response->as_string;

  jcmp_deeply(
    $res->sentence(0)->arguments->{newState},
    $state,
    'state has not changed'
  );

  jcmp_deeply(
    $res->sentence(1)->arguments->{list},
    [],
    "got empty list in getMessages response"
  ) or diag explain $res->as_stripped_struct;
});

done_testing;
