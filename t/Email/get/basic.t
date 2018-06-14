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

test "Email/get with no ids" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $res = $tester->request({
    using => [ "ietf:jmapmail" ],
    methodCalls => [[
      "Email/get" => { ids => [] },
    ]],
  });
  ok($res->is_success, "Email/get")
    or diag explain $res->http_response->as_string;

  jcmp_deeply(
    $res->single_sentence("Email/get")->arguments,
    superhashof({
      accountId => jstr($self->context->accountId),
      state     => jstr(),
      list      => [],
    }),
    "Response for ids => [] looks good",
  ) or diag explain $res->as_stripped_triples;
};

test "bodyProperties" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $mbox = $self->context->create_mailbox;
  my $message = $mbox->add_message;

  subtest "no bodyProperties specified, defaults returned" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $message->id ],
          properties => [ 'textBody' ],
        },
      ]],
    });
    ok($res->is_success, "Email/get")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Email/get")->arguments,
      superhashof({
        accountId => jstr($self->context->accountId),
        state     => jstr(),
        list      => [{
          id => $message->id,
          textBody => [{
            partId      => jstr(),
            blobId      => jstr(),
            size        => jnum(),
            name        => undef,
            type        => 'text/plain',
            charset     => 'us-ascii', # XXX ? Legit? -- alh, 2018-06-14
            disposition => undef,
            cid         => undef,
            language    => any([], undef),
            location    => undef,
          }],
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };
};

run_me;
done_testing;
