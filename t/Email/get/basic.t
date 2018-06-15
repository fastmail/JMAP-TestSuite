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

use utf8;

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

  my $from    = "test$$\@example.net";
  my $to      = "recip$$\@example.net";
  my $subject = "A subject for $$";

  my $message = $mbox->add_message({
    from    => $from,
    to      => $to,
    subject => $subject,
  });

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

  subtest "limit to no body properties" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $message->id ],
          properties => [ 'textBody' ],
          bodyProperties => [],
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
          textBody => [{}],
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "limit to all body properties" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $message->id ],
          properties => [ 'textBody' ],
          bodyProperties => [qw(
            partId blobId size headers name type charset disposition
            cid language location subParts
          )],
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
            subParts    => [],
            headers     => [
              {
                name  => 'From',
                value => re(qr/\Q$from\E/),
              }, {
                name  => 'To',
                value => re(qr/\Q$to\E/),
              }, {
                name  => 'Subject',
                value => re(qr/\Q$subject\E/),
              }, {
                name  => 'Message-Id',
                value => re(qr/<.*>/),
              }, {
                name  => 'Date',
                value => re(qr/\w/),
              }, {
                name  => 'MIME-Version',
                value => re(qr/1\.0/),
              },
            ],
          }],
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "limit to some body properties" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $message->id ],
          properties => [ 'textBody' ],
          bodyProperties => [qw(
            size name type
          )],
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
            size        => jnum(),
            name        => undef,
            type        => 'text/plain',
          }],
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };
};

test "fetchTextBodyValues" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $mbox = $self->context->create_mailbox;

  my $body = "an email body $$";

  my $message = $mbox->add_message({ body => $body });

  subtest "no fetchTextBodyValues supplied" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $message->id ],
          properties => [ 'textBody', 'bodyValues' ],
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
          bodyValues => {},
          textBody => [
            superhashof({ partId => jstr() }),
          ],
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "explicit false fetchTextBodyValues supplied" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $message->id ],
          properties => [ 'textBody', 'bodyValues' ],
          fetchTextBodyValues => jfalse(),
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
          bodyValues => {},
          textBody => [
            superhashof({ partId => jstr() }),
          ],
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "explicit true fetchTextBodyValues supplied" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $message->id ],
          properties => [ 'bodyValues', 'textBody' ],
          fetchTextBodyValues => jtrue(),
        },
      ]],
    });
    ok($res->is_success, "Email/get")
      or diag explain $res->http_response->as_string;

    my $arg = $res->single_sentence("Email/get")->arguments;

    my $part_id = $arg->{list}[0]{textBody}[0]{partId};
    ok(defined $part_id, 'we have a part id');

    jcmp_deeply(
      $arg->{list}[0]{bodyValues},
      {
        $part_id => {
          value             => $body,
          isTruncated       => jbool(),
          isEncodingProblem => jbool(),
        },
      },
      "bodyValues looks right"
    ) or diag explain $res->as_stripped_triples;
  };
};

test "fetchHTMLBodyValues" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $mbox = $self->context->create_mailbox;

  my $body = "an email body $$";

  my $message = $mbox->add_message({ body => $body });

  subtest "no fetchHTMLBodyValues supplied" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $message->id ],
          properties => [ 'htmlBody', 'bodyValues' ],
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
          bodyValues => {},
          htmlBody => [
            superhashof({ partId => jstr() }),
          ],
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "explicit false fetchHTMLBodyValues supplied" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $message->id ],
          properties => [ 'htmlBody', 'bodyValues' ],
          fetchHTMLBodyValues => jfalse(),
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
          bodyValues => {},
          htmlBody => [
            superhashof({ partId => jstr() }),
          ],
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "explicit true fetchHTMLBodyValues supplied" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $message->id ],
          properties => [ 'bodyValues', 'htmlBody' ],
          fetchHTMLBodyValues => jtrue(),
        },
      ]],
    });
    ok($res->is_success, "Email/get")
      or diag explain $res->http_response->as_string;

    my $arg = $res->single_sentence("Email/get")->arguments;

    my $part_id = $arg->{list}[0]{htmlBody}[0]{partId};
    ok(defined $part_id, 'we have a part id');

    jcmp_deeply(
      $arg->{list}[0]{bodyValues},
      {
        $part_id => {
          value             => $body,
          isTruncated       => jbool(),
          isEncodingProblem => jbool(),
        },
      },
      "bodyValues looks right"
    ) or diag explain $res->as_stripped_triples;
  };
};

test "fetchAllBodyValues" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $mbox = $self->context->create_mailbox;

  my $body = "an email body $$";

  my $message = $mbox->add_message({ body => $body });

  subtest "no fetchAllBodyValues supplied" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $message->id ],
          properties => [ 'bodyStructure', 'bodyValues' ],
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
          bodyValues => {},
          bodyStructure => superhashof({ partId => jstr() }),
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "explicit false fetchAllBodyValues supplied" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $message->id ],
          properties => [ 'bodyStructure', 'bodyValues' ],
          fetchAllBodyValues => jfalse(),
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
          bodyValues => {},
          bodyStructure => superhashof({ partId => jstr() }),
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "explicit true fetchAllBodyValues supplied" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $message->id ],
          properties => [ 'bodyStructure', 'bodyValues' ],
          fetchAllBodyValues => jtrue(),
        },
      ]],
    });
    ok($res->is_success, "Email/get")
      or diag explain $res->http_response->as_string;

    my $arg = $res->single_sentence("Email/get")->arguments;

    my $part_id = $arg->{list}[0]{bodyStructure}{partId};
    ok(defined $part_id, 'we have a part id');

    jcmp_deeply(
      $arg->{list}[0]{bodyValues},
      {
        $part_id => {
          value             => $body,
          isTruncated       => jbool(),
          isEncodingProblem => jbool(),
        },
      },
      "bodyValues looks right"
    ) or diag explain $res->as_stripped_triples;
  };
};

test "maxBodyValueBytes" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $mbox = $self->context->create_mailbox;

  my $body = "1234☃"; # snowman is 3 bytes (E2 98 83)

  my $message = $mbox->add_message({
    attributes => {
      content_type => 'text/plain',
      charset      => 'utf8',
      encoding     => 'quoted-printable',
    },
    body_str => $body,
  });

  subtest "invalid values" => sub {
    for my $invalid (-5, 0, "cat", "1", {}, [], jtrue, undef) {
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Email/get" => {
            ids               => [ $message->id ],
            properties        => [ 'bodyStructure', 'bodyValues' ],
            maxBodyValueBytes => $invalid,
          },
        ]],
      });
      ok($res->is_success, "Email/get")
        or diag explain $res->http_response->as_string;

      jcmp_deeply(
        $res->sentence_named('error')->arguments,
        {
          type => 'invalidArguments',
          arguments => [ 'maxBodyValueBytes' ], # XXX - not to spec
        },
        "got correct error"
      ) or diag explain $res->as_stripped_triples;
    }
  };

  subtest "truncate is higher than actual number of bytes" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids                => [ $message->id ],
          properties         => [ 'bodyStructure', 'bodyValues' ],
          fetchAllBodyValues => jtrue(),
          maxBodyValueBytes  => 500,
        },
      ]],
    });
    ok($res->is_success, "Email/get")
      or diag explain $res->http_response->as_string;

    my $arg = $res->single_sentence("Email/get")->arguments;

    my $part_id = $arg->{list}[0]{bodyStructure}{partId};
    ok(defined $part_id, 'we have a part id');

    jcmp_deeply(
      $arg->{list}[0]{bodyValues}{$part_id}{value},
      $body,
      'body value truncated correctly',
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "truncate between single-byte characters" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids                => [ $message->id ],
          properties         => [ 'bodyStructure', 'bodyValues' ],
          fetchAllBodyValues => jtrue(),
          maxBodyValueBytes  => 3,
        },
      ]],
    });
    ok($res->is_success, "Email/get")
      or diag explain $res->http_response->as_string;

    my $arg = $res->single_sentence("Email/get")->arguments;

    my $part_id = $arg->{list}[0]{bodyStructure}{partId};
    ok(defined $part_id, 'we have a part id');

    jcmp_deeply(
      $arg->{list}[0]{bodyValues}{$part_id}{value},
      '123',
      'body value truncated correctly',
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "truncate does not break UTF-8" => sub {
    for my $mid_snowman (5, 6) {
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Email/get" => {
            ids                => [ $message->id ],
            properties         => [ 'bodyStructure', 'bodyValues' ],
            fetchAllBodyValues => jtrue(),
            maxBodyValueBytes  => $mid_snowman,
          },
        ]],
      });
      ok($res->is_success, "Email/get")
        or diag explain $res->http_response->as_string;

      my $arg = $res->single_sentence("Email/get")->arguments;

      my $part_id = $arg->{list}[0]{bodyStructure}{partId};
      ok(defined $part_id, 'we have a part id');

      # Since we're asking for < 7 bytes and the snowman accounts for
      # bytes 5 and 6, and 7, the server MUST NOT EXCEED our request and so
      # must return everything before the snowman but not include it.
      jcmp_deeply(
        $arg->{list}[0]{bodyValues}{$part_id}{value},
        '1234',
        'body value truncated correctly',
      ) or diag explain $res->as_stripped_triples;
    }
  };

  subtest "request at boundary of email/utf8 gives us all data" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids                => [ $message->id ],
          properties         => [ 'bodyStructure', 'bodyValues' ],
          fetchAllBodyValues => jtrue(),
          maxBodyValueBytes  => 7,
        },
      ]],
    });
    ok($res->is_success, "Email/get")
      or diag explain $res->http_response->as_string;

    my $arg = $res->single_sentence("Email/get")->arguments;

    my $part_id = $arg->{list}[0]{bodyStructure}{partId};
    ok(defined $part_id, 'we have a part id');

    jcmp_deeply(
      $arg->{list}[0]{bodyValues}{$part_id}{value},
      $body,
      'body value not truncated with exact match length of bytes',
    ) or diag explain $res->as_stripped_triples;
  };
};

run_me;
done_testing;
