use strict;
use warnings;

use JMAP::TestSuite;
use Test::More;

my $server = JMAP::TestSuite->get_server;

$server->simple_test(sub {
  my ($context) = @_;

  # We should be able to pass junk (like an integer sinceState instead of a
  # string sinceState like the spec requires) and get back a sensible JSON
  # blob telling us what we did wrong.
  my $res = $context->tester->request([
    [
      getMessageUpdates => {
        sinceState => 0, # "0" works fine though for example
      },
    ]
  ]);

  ok($res->is_success, 'called getMessageUpdates')
    or diag explain $res->http_response->as_string;
});

done_testing;
