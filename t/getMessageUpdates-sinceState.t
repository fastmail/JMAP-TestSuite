use strict;
use warnings;
use Test::Routine;
use Test::Routine::Util;

with 'JMAP::TestSuite::Tester';

use JMAP::TestSuite::Util qw(batch_ok pristine_test);

use Test::Deep::JType;
use Test::More;
use Test::Abortable;

test "getMesageUpdates-sinceState" => sub {
  my ($self) = @_;

  my $context = $self->context;

  # We should be able to pass junk (like an integer sinceState instead of a
  # string sinceState like the spec requires) and get back a sensible JSON
  # blob telling us what we did wrong.
  my $res = $context->tester->request({
    methodCalls => [
      [
        'Email/queryChanges' => {
          # JMAP expects this state value to be a string, so this call may be
          # rejected, but it shouldn't cause a server error.
          sinceState => jnum(0),
        },
      ],
    ],
  });

  ok($res->is_success, 'called getMessageUpdates')
    or diag explain $res->http_response->as_string;
};

run_me;
done_testing;
