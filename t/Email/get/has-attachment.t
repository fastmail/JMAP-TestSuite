use jmaptest;

use Email::MIME;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;

  subtest "no attachments" => sub {
    my $message = $mbox->add_message({
      email_type => 'provided',
      email      => Email::MIME->create(
        header_str => [
          MessageId => Email::MessageID->new->in_brackets,
          From      => 'test@example.com',
          To        => 'test@exapmle.com',
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
      or diag explain $res->http_response->as_string;

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
      or diag explain $res->http_response->as_string;

    my $email = $res->sentence_named("Email/get")->arguments->{list}[0];
    jcmp_deeply(
      $email,
      superhashof({ hasAttachment => jtrue() }),
      "Email with attachments is hasAttachment: true",
    ) or diag explain $res->as_stripped_triples;
  };
};
