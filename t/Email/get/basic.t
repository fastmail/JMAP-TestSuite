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
          isTruncated       => jfalse(),
          isEncodingProblem => jfalse(),
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
          isTruncated       => jfalse(),
          isEncodingProblem => jfalse(),
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
          isTruncated       => jfalse(),
          isEncodingProblem => jfalse(),
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
      $arg->{list}[0]{bodyValues}{$part_id},
      superhashof({
        value => $body,
        isTruncated => jfalse(),
      }),
      'body value not truncated',
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
      $arg->{list}[0]{bodyValues}{$part_id},
      superhashof({
        value => '123',
        isTruncated => jtrue(),
      }),
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
        $arg->{list}[0]{bodyValues}{$part_id},
        superhashof({
          value => '1234',
          isTruncated => jtrue(),
        }),
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
      $arg->{list}[0]{bodyValues}{$part_id},
      superhashof({
        value => $body,
        isTruncated => jfalse(),
      }),
      'body value not truncated with exact match length of bytes',
    ) or diag explain $res->as_stripped_triples;
  };
};

test "properties" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $mbox = $self->context->create_mailbox;

  my $from    = "test$$\@example.net";
  my $to      = "recip$$\@example.net";
  my $subject = "A subject for $$";

  my $message = $mbox->add_message;
  my $reply = $message->reply({
    from    => $from,
    to      => $to,
    subject => $subject,
    headers => [
      Sender     => "sender$from",
      CC         => "cc$from",
      BCC        => "bcc$from",
      'Reply-To' => "rt$from",
    ],
  });

  my $em_msg_id = $message->messageId->[0];
  my $reply_msg_id = $reply->messageId->[0];

  my $empty = any([], undef);

  subtest "no properties specified, defaults returned" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $reply->id ],
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
          id            => $reply->id,
          blobId        => jstr(),
          threadId      => jstr(),
          mailboxIds    => {
            $mbox->id . "" => jtrue(),
          },
          keywords      => superhashof({}),
          size          => jnum(),
          receivedAt    => re('\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\dZ'),
          messageId     => [ $reply_msg_id ],
          inReplyTo     => [ $em_msg_id ],
          references    => [ $em_msg_id ],
          sender        => [{ name => undef, email => "sender$from" }],
          from          => [{ name => undef, email => $from }],
          to            => [{ name => undef, email => $to }],
          cc            => [{ name => undef, email => "cc$from" }],
          bcc           => [{ name => undef, email => "bcc$from" }],
          replyTo       => [{ name => undef, email => "rt$from" }],
          subject       => $subject,
          sentAt        => re('\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\dZ'),
          hasAttachment => jtrue(), # XXX FALSE (cyrus...)
          preview       => jstr(),
          bodyValues    => {},
          textBody => [
            superhashof({ partId => jstr() }),
          ],
          htmlBody => [
            superhashof({ partId => jstr() }),
          ],
#          attachments  => $empty, # XXX, attachments is the new norm!
          attachedEmails => [],
          attachedFiles => [],
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "limit to no properties" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $reply->id ],
          properties => [],
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
          id => $reply->id,
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "limit to all properties" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $reply->id ],
          properties => [qw(
            id blobId threadId mailboxIds keywords size
            receivedAt messageId inReplyTo references sender from
            to cc bcc replyTo subject sentAt hasAttachment
            preview bodyValues textBody htmlBody attachments
            headers bodyStructure
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
          id            => $reply->id,
          blobId        => jstr(),
          threadId      => jstr(),
          mailboxIds    => {
            $mbox->id . "" => jtrue(),
          },
          keywords      => superhashof({}),
          size          => jnum(),
          receivedAt    => re('\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\dZ'),
          messageId     => [ $reply_msg_id ],
          inReplyTo     => [ $em_msg_id ],
          references    => [ $em_msg_id ],
          sender        => [{ name => undef, email => "sender$from" }],
          from          => [{ name => undef, email => $from }],
          to            => [{ name => undef, email => $to }],
          cc            => [{ name => undef, email => "cc$from" }],
          bcc           => [{ name => undef, email => "bcc$from" }],
          replyTo       => [{ name => undef, email => "rt$from" }],
          subject       => $subject,
          sentAt        => re('\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\dZ'),
          hasAttachment => jtrue(), # XXX FALSE (cyrus...)
          preview       => jstr(),
          bodyValues    => {},
          textBody => [
            superhashof({ partId => jstr() }),
          ],
          htmlBody => [
            superhashof({ partId => jstr() }),
          ],
#          attachments  => $empty, # XXX, attachments is the new norm!
          headers => [
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
              name  => 'Sender',
              value => re(qr/\w/),
            }, {
              name  => 'CC',
              value => re(qr/\w/),
            }, {
              name  => 'BCC',
              value => re(qr/\w/),
            }, {
              name  => 'Reply-To',
              value => re(qr/\w/),
            }, {
              name  => 'In-Reply-To',
              value => re(qr/\w/),
            }, {
              name  => 'References',
              value => re(qr/\w/),
            }, {
              name  => 'Date',
              value => re(qr/\w/),
            }, {
              name  => 'MIME-Version',
              value => re(qr/1\.0/),
            },
          ],
          bodyStructure => superhashof({
            partId => jstr(),
          }),
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "limit to some properties" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $reply->id ],
          properties => [qw(
            threadId size preview
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
          id       => $reply->id,
          threadId => jstr(),
          size     => jnum(),
          preview  => jstr(),
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };
};

test "header:{header-field-name}" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $mbox = $self->context->create_mailbox;

  my $from    = "test$$\@example.net";
  my $to      = "recip$$\@example.net";
  my $subject = "A subject for $$";
  my $date    = 'Mon, 18 Jun 2018 16:51:28 -0400';
  my $ls      = 'https://example.net';

  my $message = $mbox->add_message({
    from    => $from,
    to      => $to,
    subject => $subject,
    headers => [
      'List-Subscribe' => $ls,
      Date             => $date,
      Single           => 'A single value',
      Multiple         => '1st value',
      Multiple         => '2nd value',
      Multiple         => '3rd value',
    ],
  });

  my $em_msg_id = $message->messageId->[0];

  subtest "No as: prefix - default header-form Raw" => sub {
    # Let's test a few that have different parsed forms
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $message->id ],
          properties => [qw(
            header:DAte
            header:Message-Id
            header:FROm
            header:SuBject
            header:List-Subscribe
            header:None
            header:Multiple
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
          id                      => $message->id,
          'header:DAte'           => " $date",
          'header:Message-Id'     => re(qr/^\s<[^>]+>$/),
          'header:FROm' =>        => " $from",
          'header:SuBject'        => " $subject",
          'header:List-Subscribe' => " $ls",
          'header:None'           => undef,
          'header:Multiple'       => ' 3rd value',
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest ":all prefix, single, multi, and none" => sub {
    # Let's test a few that have different parsed forms
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $message->id ],
          properties => [qw(
            header:SinglE:all
            header:Multiple:all
            header:None:all
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
          id                      => $message->id,
          'header:SinglE:all'   => [ ' A single value' ],
          'header:Multiple:all' => [
            ' 1st value',
            ' 2nd value',
            ' 3rd value',
          ],
          'header:None:all'     => [],
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "suffix order must be :as{foo}:all" => sub {
    # Let's test a few that have different parsed forms
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $message->id ],
          properties => [qw(
            header:None:all:asRaw
          )],
        },
      ]],
    });
    ok($res->is_success, "Email/get")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("error")->arguments,
      superhashof({
        type => 'invalidArguments',
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "asText" => sub {
    my $message = $mbox->add_message({
      headers => [
        # Make sure these all asText properly
        subject   => "☃",
        comment   => "☃☃",
        'list-id' => "☃☃☃",
        'X-Foo'   => "☃☃☃☃",

        # NFC check on utf8. ANGSTROM SIGN NFCd should become
        # LATIN CAPITAL LETTER A WITH RING ABOVE
        'X-NFC'   => "\N{ANGSTROM SIGN}",
      ],
      raw_headers => [
        'X-Fold'  => " " . ("a" x 50) . " " . ("b" x 50),
      ]
    });

    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $message->id ],
          properties => [qw(
            header:subject:asRaw
            header:comment:asRaw
            header:list-id:asRaw
            header:x-foo:asRaw
            header:x-nfc:asRaw
            header:x-fold:asRaw
            header:subject:asText
            header:comment:asText
            header:list-id:asText
            header:x-foo:asText
            header:x-nfc:asText
            header:x-fold:asText
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
          id                      => $message->id,
          'header:subject:asRaw'  => " =?UTF-8?B?4piD?=",
          'header:comment:asRaw'  => " =?UTF-8?B?4piD4piD?=",
          'header:list-id:asRaw'  => " =?UTF-8?B?4piD4piD4piD?=",
          'header:x-foo:asRaw'    => " =?UTF-8?B?4piD4piD4piD4piD?=",
          'header:x-nfc:asRaw'    => " =?UTF-8?B?4oSr?=",
          'header:x-fold:asRaw'   => "  " . ("a" x 50) . "\r\n " . ("b" x 50),
          'header:subject:asText' => "☃",
          'header:comment:asText' => "☃☃",
          'header:list-id:asText' => "☃☃☃",
          'header:x-foo:asText'   => "☃☃☃☃",
          'header:x-nfc:asText'   => "\N{LATIN CAPITAL LETTER A WITH RING ABOVE}",
          'header:x-fold:asText'  => ("a" x 50) . " " . ("b" x 50),
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "asAddresses" => sub {
    my $name = "Foo \\S";
    my $email = "foos$$\@example.net";

    my $value = qq{"$name" <$email>};

    my $expect_name = $name;

    # \S -> S (quoted-pair)
    $expect_name =~ s/\\//g;

    # XXX - Really this should be in headers_raw but can't because it won't
    # override defaults headers To... -- alh, 2018-06-20
    my $to_value = qq{"$expect_name" <$email>};

    # No name
    my $from_value = 'foo@example.net';

    my @hlist = qw(
      Sender
      Reply-To
      Cc
      Bcc
      Resent-From
      Resent-Sender
      Resent-Reply-To
      Resent-To
      Resent-Cc
      X-Foo
    );

    my $long_name = "a" x 58;
    my $long_email = 'foo@example.net';

    my $long_value = qq{"$long_name" <$long_email>};

    my $group_value = 'A group: foo <foo@example.org>,"bar d" <bar@example.org>;';

    my $message = $mbox->add_message({
      raw_headers => [
        ( map {;
          $_ => $value,
        } @hlist, ),
        'Resent-Bcc' => $long_value,
      ],
      # raw_headers doesn't override these sadly. XXX - To fix
      headers => [
        From      => $from_value,
        To        => $value,
        'X-Group' => $group_value,
      ],
    });

    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $message->id ],
          properties => [
            ( map {;
              "header:$_:asRaw",
            } @hlist, ),
            ( map {;
              "header:$_:asAddresses",
            } @hlist, ),
            qw(
              header:From:asRaw
              header:From:asAddresses
              header:To:asRaw
              header:To:asAddresses
              header:Resent-Bcc:asRaw
              header:Resent-Bcc:asAddresses
              header:X-Group:asRaw
              header:X-Group:asAddresses
            ),
          ],
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
          id                      => $message->id,
          ( map {;
            "header:$_:asRaw" => " $value",
          } @hlist, ),
          ( map {;
            "header:$_:asAddresses" => [{
              name  => $expect_name,
              email => $email,
            }],
          } @hlist, ),
          'header:From:asRaw' => " $from_value",
          'header:To:asRaw'   => " $to_value",
          'header:From:asAddresses' => [{
            name => undef,
            email => $from_value,
          }],
          'header:To:asAddresses' => [{
            name => $expect_name,
            email => $email,
          }],
          'header:Resent-Bcc:asRaw' => qq{ "$long_name"\r\n <$long_email>},
          'header:Resent-Bcc:asAddresses' => [{
            name  => $long_name,
            email => $long_email,
          }],
          'header:X-Group:asRaw' => " $group_value",
          'header:X-Group:asAddresses' => [
            {
              name  => 'A group',
              email => undef,
            }, {
              name  => 'foo',
              email => 'foo@example.org',
            }, {
              name  => 'bar d',
              email => 'bar@example.org',
            }, { # XXX - Cyrus adding this in? Why? -- alh, 2018-06-20
              name => undef,
              email => undef,
            },
          ],
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "asMessageIds" => sub {
    my @hlist = qw(
      Message-ID
      In-Reply-To
      Resent-Message-ID
      X-Foo
    );

    my $mid1 = 'foo@example.com';
    my $value = "<$mid1>";

    my $mid2 = ('f' x 45) . '@example.com';
    my $mid3 = 'bar@example.com';

    my $long_value = "<$mid2> <$mid3>";

    my $message = $mbox->add_message({
      headers => [
        ( map {;
          $_ => $value,
        } @hlist, ),
        References => $long_value,
      ],
    });

    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $message->id ],
          properties => [
            ( map {;
              "header:$_:asRaw",
            } @hlist, ),
            ( map {;
              "header:$_:asMessageIds",
            } @hlist, ),
            qw(
              header:References:asRaw
              header:References:asMessageIds
            ),
          ],
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
          id                      => $message->id,
          ( map {;
            "header:$_:asRaw" => " $value",
          } @hlist, ),
          ( map {;
            "header:$_:asMessageIds" => [ $mid1 ],
          } @hlist, ),
          'header:References:asRaw' => " <$mid2>\r\n <$mid3>",
          'header:References:asMessageIds' => [ $mid2, $mid3 ],
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "asDate" => sub {
    my @hlist = qw(
      Date
      Resent-Date
      X-Foo
    );

    my $value = "Thu, 13 Feb 1969 23:32 -0330 (Newfoundland Time)";

    # 13th at 23:32 + 3.5h...
    my $expect = "1969-02-14T03:02:00Z";

    my $message = $mbox->add_message({
      raw_headers => [
        ( map {;
          $_ => $value,
        } @hlist, ),
      ],
    });

    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $message->id ],
          properties => [
            ( map {;
              "header:$_:asRaw",
            } @hlist, ),
            ( map {;
              "header:$_:asDate",
            } @hlist, ),
          ],
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
          id                          => $message->id,
          ( map {;
            "header:$_:asRaw" => " $value",
          } @hlist, ),
          ( map {;
            "header:$_:asDate" => "$expect",
          } @hlist, ),
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "asURLs" => sub {
    my @hlist = qw(
      List-Help
      List-Unsubscribe
      List-Subscribe
      List-Post
      List-Owner
      List-Archive
      X-Foo
    );

    my $url1 = "http://example.net";
    my $url2 = "http://example.org/" . ("a" x 35);

    my $value = "<$url1> <$url2>";

    my $message = $mbox->add_message({
      raw_headers => [
        ( map {;
          $_ => $value,
        } @hlist, ),
      ],
    });

    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Email/get" => {
          ids        => [ $message->id ],
          properties => [
            ( map {;
              "header:$_:asRaw",
            } @hlist, ),
            ( map {;
              "header:$_:asURLs",
            } @hlist, ),
          ],
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
          ( map {;
            "header:$_:asRaw" => " <$url1>\r\n <$url2>",
          } @hlist, ),
          ( map {;
            "header:$_:asURLs" => [ $url1, $url2 ],
          } @hlist, ),
        }],
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };
};

run_me;
done_testing;
