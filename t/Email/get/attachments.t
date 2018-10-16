use jmaptest;

use JMAP::TestSuite::Util qw(part multipart parts cpart cmultipart);
use Email::MIME;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;

  subtest "image/audio/video in text only, attached" => sub {
    my $email = cmultipart("alternative", [
      cmultipart("mixed", [
        cpart("text/plain", "a"),
        cpart("image/jpeg", "b"),
        cpart("audio/mp3",  "c"),
        cpart("video/avi",  "d"),
      ]),
      cpart("text/html", "e"),
    ]);

    my $message = $mbox->add_message({
      email_type => 'provided',
      email      => $email->as_string,
    });

    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [ qw(
          bodyStructure
          textBody
          htmlBody
          attachments
        ) ],
      },
    ]]);
    ok($res->is_success, "Email/get")
      or diag explain $res->response_payload;

    jcmp_deeply(
      $res->sentence_named("Email/get")->arguments->{list}[0]{bodyStructure},
      multipart('alternative', [
        multipart('mixed', [
          part("text/plain"),
          part("image/jpeg"),
          part("audio/mp3"),
          part("video/avi"),
        ]),
        part("text/html"),
      ]),
      "bodyStructure parts look right"
    ) or diag explain $res->as_stripped_triples;

    jcmp_deeply(
      $res->sentence_named("Email/get")->arguments->{list}[0],
      superhashof({
        textBody => [ map { part($_) } qw(text/plain image/jpeg audio/mp3 video/avi) ],
        htmlBody => [ part('text/html') ],
      }),
      "textBody and htmlBody are correct"
    ) or diag explain $res->as_stripped_triples;

    jcmp_deeply(
      $res->sentence_named("Email/get")->arguments->{list}[0]{attachments},
      [ parts(qw(image/jpeg audio/mp3 video/avi)) ],
      "attachments are correct"
    );
  };

  subtest "image/audio/video in html only, attached" => sub {
    my $email = cmultipart("alternative", [
      cpart("text/plain", "a"),
      cmultipart("mixed", [
        cpart("text/html",  "b"),
        cpart("image/jpeg", "c"),
        cpart("audio/mp3",  "d"),
        cpart("video/avi",  "e"),
      ]),
    ]);

    my $message = $mbox->add_message({
      email_type => 'provided',
      email      => $email->as_string,
    });

    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [ qw(
          bodyStructure
          textBody
          htmlBody
          attachments
        ) ],
      },
    ]]);
    ok($res->is_success, "Email/get")
      or diag explain $res->response_payload;

    jcmp_deeply(
      $res->sentence_named("Email/get")->arguments->{list}[0]{bodyStructure},
      multipart('alternative', [
        part("text/plain"),
        multipart('mixed', [
          part("text/html"),
          part("image/jpeg"),
          part("audio/mp3"),
          part("video/avi"),
        ]),
      ]),
      "bodyStructure parts look right"
    ) or diag explain $res->as_stripped_triples;

    jcmp_deeply(
      $res->sentence_named("Email/get")->arguments->{list}[0],
      superhashof({
        textBody => [ part('text/plain')],
        htmlBody => [ map { part($_) } qw(text/html image/jpeg audio/mp3 video/avi) ],
      }),
      "textBody and htmlBody are correct"
    ) or diag explain $res->as_stripped_triples;

    jcmp_deeply(
      $res->sentence_named("Email/get")->arguments->{list}[0]{attachments},
      [ parts(qw(image/jpeg audio/mp3 video/avi)) ],
      "attachments are correct"
    );
  };

  subtest "image/audio/video in text and html, not attached" => sub {
    my $email = cmultipart("mixed", [
      cmultipart("alternative", [
        cpart("text/plain", "a"),
        cpart("text/html",  "b")
      ]),
      cpart("image/jpeg", "c"),
      cpart("audio/mp3",  "d"),
      cpart("video/avi",  "e"),
    ]);

    my $message = $mbox->add_message({
      email_type => 'provided',
      email      => $email->as_string,
    });

    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [ qw(
          bodyStructure
          textBody
          htmlBody
          attachments
        ) ],
      },
    ]]);
    ok($res->is_success, "Email/get")
      or diag explain $res->response_payload;

    jcmp_deeply(
      $res->sentence_named("Email/get")->arguments->{list}[0]{bodyStructure},
      multipart('mixed', [
        multipart('alternative', [
          part("text/plain"),
          part("text/html"),
        ]),
        part("image/jpeg"),
        part("audio/mp3"),
        part("video/avi"),
      ]),
      "bodyStructure parts look right"
    ) or diag explain $res->as_stripped_triples;

    jcmp_deeply(
      $res->sentence_named("Email/get")->arguments->{list}[0],
      superhashof({
        textBody => [ map { part($_) } qw(text/plain image/jpeg audio/mp3 video/avi) ],
        htmlBody => [ map { part($_) } qw(text/html image/jpeg audio/mp3 video/avi) ],
      }),
      "textBody and htmlBody are correct"
    ) or diag explain $res->as_stripped_triples;

    jcmp_deeply(
      $res->sentence_named("Email/get")->arguments->{list}[0]{textBody},
      [ map { part($_) } qw(text/plain image/jpeg audio/mp3 video/avi) ],
      "textBody is correct"
    ) or diag explain $res->as_stripped_triples;

    jcmp_deeply(
      $res->sentence_named("Email/get")->arguments->{list}[0]{attachments},
      [ ],
      "attachments are correct"
    );
  };

  subtest "no attachments" => sub {
    my $message = $mbox->add_message({
      email_type => 'provided',
      email      => Email::MIME->create(
        header_str => [
          From => 'test@example.com',
          To   => 'test@exapmle.com',
        ],
        parts => [
          "Main body",
        ],
      )->as_string,
    });

    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [ 'attachments', 'hasAttachment', ],
      },
    ]]);
    ok($res->is_success, "Email/get")
      or diag explain $res->response_payload;

    my $email = $res->sentence_named("Email/get")->arguments->{list}[0];
    jcmp_deeply(
      $email,
      superhashof({ hasAttachment => jfalse() }),
      "Email without attachments is hasAttachment: false",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "an attachment" => sub {
    my $message = $mbox->add_message({
      email_type => 'provided',
      email      => Email::MIME->create(
        header_str => [
          From => 'test@example.com',
          To   => 'test@exapmle.com',
        ],
        parts => [
          "Main body",
          Email::MIME->create(
            attributes => {
              filename     => "report.pdf",
              content_type => "application/pdf",
              encoding     => "quoted-printable",
              name         => "report.pdf",
              disposition  => "attachment",
            },
            body => "",
          ),
        ],
      )->as_string,
    });

    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [ 'attachments', 'hasAttachment', ],
      },
    ]]);
    ok($res->is_success, "Email/get")
      or diag explain $res->response_payload;

    my $email = $res->sentence_named("Email/get")->arguments->{list}[0];
    jcmp_deeply(
      $email,
      superhashof({ hasAttachment => jtrue() }),
      "Email with attachments is hasAttachment: true",
    ) or diag explain $res->as_stripped_triples;
  };
};
