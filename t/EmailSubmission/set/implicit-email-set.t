use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
    'urn:ietf:params:jmap:submission',
  );

  my ($identity) = @{
    $tester->request([[ "Identity/get" => {} ]])
      ->single_sentence("Identity/get")->arguments->{list} // []
  };
  plan skip_all => "account has no identity to submit as" unless $identity;
  (my $from = $identity->{email}) =~ s/\A\*\@/jmaptest\@/;

  my $drafts = $account->create_mailbox;
  my $sent   = $account->create_mailbox;

  my $draft = sub {
    my ($subject) = @_;
    return $tester->request([[
      "Email/set" => {
        create => {
          draft => {
            from       => [{ email => $from }],
            to         => [{ email => $from }],
            subject    => $subject,
            keywords   => { '$draft' => jtrue() },
            mailboxIds => { $drafts->id => jtrue() },
            bodyValues => { body => { value => 'Test body.' } },
            textBody   => [{ partId => 'body', type => 'text/plain' }],
          },
        },
      },
    ]])->single_sentence("Email/set")->arguments->{created}{draft}{id};
  };

  # RFC 8621 S7.5: "a single implicit 'Email/set' call MUST be made" for
  # onSuccessUpdateEmail/onSuccessDestroyEmail, and "The response to this
  # MUST be returned after the 'EmailSubmission/set' response", with the
  # same method call id (S7.5.1).
  my $submit = sub {
    my ($email_id, %extra) = @_;

    my $res = $tester->request([[
      "EmailSubmission/set" => {
        create => { s1 => { emailId => $email_id, identityId => $identity->{id} } },
        %extra,
      },
      'sub',
    ]]);
    ok($res->is_success, "EmailSubmission/set") or diag explain $res->response_payload;

    my @sentences = $res->sentences;
    my $sub_args  = $sentences[0]->arguments;
    if (($sub_args->{notCreated}{s1}{type} // '') eq 'forbiddenToSend') {
      note("server refused to send: forbiddenToSend");
      return;
    }
    ok($sub_args->{created}{s1}, "submission created") or diag explain $sub_args;

    is(scalar @sentences, 2, "two responses") or diag explain $res->as_stripped_triples;
    is($sentences[0]->name, 'EmailSubmission/set', "EmailSubmission/set comes first");
    is($sentences[1] && $sentences[1]->name, 'Email/set', "then the implicit Email/set");
    is($sentences[1] && $sentences[1]->client_id, 'sub', "with the same method call id");

    return $sentences[1] && $sentences[1]->arguments;
  };

  subtest "onSuccessUpdateEmail" => sub {
    my $email_id = $draft->('Test onSuccessUpdateEmail');
    ok(defined $email_id, "created a draft") or return;

    my $email_set = $submit->(
      $email_id,
      onSuccessUpdateEmail => {
        '#s1' => {
          'mailboxIds/' . $drafts->id => undef,
          'mailboxIds/' . $sent->id   => jtrue(),
          'keywords/$draft'           => undef,
          'keywords/$seen'            => jtrue(),
        },
      },
    ) or return;

    ok(exists $email_set->{updated}{$email_id}, "implicit Email/set updated the draft")
      or diag explain $email_set;

    $tester->request_ok(
      [ "Email/get" => { ids => [ $email_id ], properties => [ 'mailboxIds', 'keywords' ] } ],
      superhashof({
        list => [ superhashof({
          mailboxIds => { $sent->id => jtrue() },
          keywords   => { '$seen' => jtrue() },
        }) ],
      }),
      "Email moved and its keywords patched",
    );
  };

  subtest "onSuccessDestroyEmail" => sub {
    my $email_id = $draft->('Test onSuccessDestroyEmail');
    ok(defined $email_id, "created a draft") or return;

    my $email_set = $submit->($email_id, onSuccessDestroyEmail => [ '#s1' ]) or return;

    jcmp_deeply($email_set->{destroyed}, [ $email_id ], "implicit Email/set destroyed the draft")
      or diag explain $email_set;

    $tester->request_ok(
      [ "Email/get" => { ids => [ $email_id ] } ],
      superhashof({ list => [], notFound => [ $email_id ] }),
      "Email is gone",
    );
  };
};
