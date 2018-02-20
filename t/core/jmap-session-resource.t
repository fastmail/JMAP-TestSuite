use strict;
use warnings;

use JMAP::TestSuite;
use JMAP::TestSuite::Util qw(batch_ok);

use Test::Deep;
use Test::Deep::JType;
use Test::More;
use JSON qw(decode_json);
use JSON::Typist;

my $server = JMAP::TestSuite->get_server;

$server->simple_test(sub {
  my ($context) = @_;

  my $tester = $context->tester;
  my $res = $tester->ua->get($tester->api_uri);
  ok($res->is_success, "GET " . $tester->api_uri);

  my $data = eval { decode_json($res->decoded_content) };
  ok($data, 'Got JSON response')
    or diag("Invalid json?: " . $res->decoded_content);

  my $typed = JSON::Typist->new->apply_types($data);

  jcmp_deeply(
    $typed,
    {
      username => jstr,
      accounts => {
        'example' => {
          name => jstr,
          isPrimary => jbool,
          isReadOnly => jbool,
#          hasDataFor => [jstr],
        },
      },
      capabilities => superhashof({
        'ietf:jmap' => {
          maxSizeUpload => jnum,
          maxConcurrentUpload => jnum,
          maxSizeRequest => jnum,
          maxConcurrentRequests => jnum,
          maxCallsInRequest => jnum,
          maxObjectsInGet => jnum,
          maxObjectsInSet => jnum,
          collationAlgorithms => ignore(),
        },
      }),
      apiUrl => jstr,
      downloadUrl => jstr,
      uploadUrl => jstr,
#      eventSourceUrl => jstr,
    },
    'Response looks good',
  ) or diag explain $data;
});

done_testing;
