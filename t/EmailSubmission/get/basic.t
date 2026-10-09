use jmaptest;

attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
    'urn:ietf:params:jmap:submission',
  );

  my $mb_res = $tester->request([[
    "Mailbox/get" => {},
  ]]);
  my @mailboxes = @{ $mb_res->single_sentence("Mailbox/get")->arguments->{list} };
  my ($drafts) = grep { ($_->{role} // '') eq 'drafts' } @mailboxes;
  $drafts //= $mailboxes[0];
  my $drafts_id = $drafts->{id};

  # Identity ids are server-assigned, so look one up.
  my ($identity) = @{
    $tester->request([[ "Identity/get" => {} ]])
      ->single_sentence("Identity/get")->arguments->{list} // []
  };
  ok($identity && $identity->{id}, "got an identity to submit as") or return;

  # RFC 8621 S6: Identity email is "The 'From' email address the client
  # MUST use"; a "*" mailbox part allows any address in that domain.
  (my $from = $identity->{email}) =~ s/\A\*\@/jmaptest\@/;

  my $email_res = $tester->request([[
    "Email/set" => {
      create => {
        draft1 => {
          from        => [{ email => $from }],
          to          => [{ email => $from }],
          subject     => 'Test EmailSubmission',
          keywords    => { '$draft' => jtrue() },
          mailboxIds  => { $drafts_id => jtrue() },
          bodyValues  => { body => { value => 'Test body.', charset => 'utf-8' } },
          textBody    => [{ partId => 'body', type => 'text/plain' }],
        },
      },
    },
  ]]);
  ok($email_res->is_success, "Email/set create draft");
  my $email_id = $email_res->single_sentence("Email/set")->arguments->{created}{draft1}{id};
  ok(defined $email_id, "got draft email id");

  my $sub_res = $tester->request([[
    "EmailSubmission/set" => {
      create => {
        s1 => {
          emailId    => $email_id,
          identityId => $identity->{id},
          envelope   => {
            mailFrom => { email => $from },
            rcptTo   => [{ email => $from }],
          },
        },
      },
    },
  ]]);
  ok($sub_res->is_success, "EmailSubmission/set") or diag explain $sub_res->response_payload;

  my $set_args = $sub_res->single_sentence("EmailSubmission/set")->arguments;
  my $sub_id = $set_args->{created}{s1}{id};

  # RFC 8621 S7.5: forbiddenToSend means the user "does not have permission
  # to send at all right now", which no request can avoid.
  my $err_type = $set_args->{notCreated}{s1}{type} // '';
  SKIP: {
    skip "server refused to send: forbiddenToSend", 2
      if $err_type eq 'forbiddenToSend';

    ok(defined $sub_id, "created a submission")
      or diag explain $set_args->{notCreated};
    skip "no submission to fetch", 1 unless defined $sub_id;

    subtest "get created submission" => sub {
      my $res = $tester->request([[
        "EmailSubmission/get" => {
          ids => [$sub_id],
        },
      ]]);
      ok($res->is_success, "EmailSubmission/get") or diag explain $res->response_payload;

      my $args = $res->single_sentence("EmailSubmission/get")->arguments;
      is(scalar @{ $args->{list} },     1, "one result");
      is(scalar @{ $args->{notFound} }, 0, "nothing not found");

      jcmp_deeply(
        $args->{list}[0],
        superhashof({
          id         => jstr($sub_id),
          emailId    => jstr($email_id),
          identityId => jstr(),
        }),
        "submission has required fields",
      ) or diag explain $args->{list}[0];
    };
  };

  subtest "get unknown submission id" => sub {
    my $res = $tester->request([[
      "EmailSubmission/get" => {
        ids => ['nonexistent-submission-id'],
      },
    ]]);
    ok($res->is_success, "EmailSubmission/get with unknown id");

    my $args = $res->single_sentence("EmailSubmission/get")->arguments;
    is(scalar @{ $args->{list} },     0, "no results");
    is(scalar @{ $args->{notFound} }, 1, "one not found");
  };

  subtest "get with empty ids" => sub {
    my $res = $tester->request([[
      "EmailSubmission/get" => {
        ids => [],
      },
    ]]);
    ok($res->is_success, "EmailSubmission/get ids=[]");

    my $args = $res->single_sentence("EmailSubmission/get")->arguments;
    is(scalar @{ $args->{list} },     0, "no results");
    is(scalar @{ $args->{notFound} }, 0, "nothing not found");
  };
};
