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

test "GETting jmap api gives us data and capabilities about the server" => sub {
  my ($self) = @_;

  my $tester = $self->tester;
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
        $self->context->accountId => {
          name => jstr,
          isPrimary => jbool,
          isReadOnly => jbool,
          hasDataFor => [jstr, jstr, jstr], # XXX - Spec updates might change
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
#      eventSourceUrl => jstr, # XXX - Spec updates might change
    },
    'Response looks good',
  ) or diag explain $data;
};

run_me;
done_testing;
