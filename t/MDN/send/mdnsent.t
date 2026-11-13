use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
    'urn:ietf:params:jmap:submission',
    'urn:ietf:params:jmap:mdn',
  );

  my ($identity) = @{
    $tester->request([[ "Identity/get" => {} ]])
      ->single_sentence("Identity/get")->arguments->{list} // []
  };
  plan skip_all => "account has no identity to send as" unless $identity;
  (my $from = $identity->{email}) =~ s/\A\*\@/jmaptest\@/;

  my $mailbox = $account->create_mailbox;

  # The receipt goes back to this account's own address.
  my $email_id = $tester->request([[
    "Email/set" => {
      create => {
        msg => {
          from       => [{ email => $from }],
          to         => [{ email => $from }],
          subject    => 'Test MDN/send',
          mailboxIds => { $mailbox->id => jtrue() },
          'header:Disposition-Notification-To:asAddresses' => [{ email => $from }],
          bodyValues => { body => { value => 'Please send a receipt.' } },
          textBody   => [{ partId => 'body', type => 'text/plain' }],
        },
      },
    },
  ]])->single_sentence("Email/set")->arguments->{created}{msg}{id};
  ok(defined $email_id, "created an Email asking for an MDN") or return;

  my $mdn = {
    forEmailId  => $email_id,
    subject     => 'Read receipt for: Test MDN/send',
    textBody    => 'This receipt shows that the email has been displayed.',
    disposition => {
      actionMode  => 'manual-action',
      sendingMode => 'mdn-sent-manually',
      type        => 'displayed',
    },
  };
  my $set_mdnsent = { '#k1' => { 'keywords/$mdnsent' => jtrue() } };

  my $send = sub {
    my (%extra) = @_;
    return $tester->request([[
      "MDN/send" => {
        identityId => $identity->{id},
        send       => { k1 => $mdn },
        %extra,
      },
    ]]);
  };

  my $keywords = sub {
    $tester->request([[
      "Email/get" => { ids => [ $email_id ], properties => [ 'keywords' ] },
    ]])->single_sentence("Email/get")->arguments->{list}[0]{keywords} // {};
  };

  subtest "without setting \$mdnsent" => sub {
    my $res = $send->();

    # RFC 9007 S2.1: "the server MUST reject an 'MDN/send' that does not
    # result in setting the keyword '$mdnsent'"; it doesn't say how.
    my ($first) = $res->sentences;
    if ($first->name eq 'MDN/send') {
      my $args = $first->arguments;
      ok(!($args->{sent} && $args->{sent}{k1}), "MDN not sent") or diag explain $args;
      ok($args->{notSent}{k1}, "MDN in notSent") or diag explain $args;
    } else {
      is($first->name, 'error', "MDN/send rejected with a method error")
        or diag explain $res->as_stripped_triples;
    }
    ok(!$keywords->()->{'$mdnsent'}, "\$mdnsent not set");
  };

  subtest "setting \$mdnsent" => sub {
    my $res = $send->(onSuccessUpdateEmail => $set_mdnsent);
    ok($res->is_success, "MDN/send") or diag explain $res->response_payload;

    my $args = $res->sentence_named("MDN/send")->arguments;
    ok($args->{sent}{k1}, "MDN sent") or diag explain $args;
    ok($keywords->()->{'$mdnsent'}, "\$mdnsent set on the Email");
  };

  subtest "a second MDN for the same Email" => sub {
    my $res = $send->(onSuccessUpdateEmail => $set_mdnsent);
    ok($res->is_success, "MDN/send") or diag explain $res->response_payload;

    # RFC 9007 S2.1: mdnAlreadySent means "The message has the '$mdnsent'
    # keyword already set."
    my $args = $res->sentence_named("MDN/send")->arguments;
    ok(!($args->{sent} && $args->{sent}{k1}), "MDN not sent again") or diag explain $args;
    jcmp_deeply(
      $args->{notSent}{k1},
      superhashof({ type => 'mdnAlreadySent' }),
      "notSent with mdnAlreadySent",
    ) or diag explain $args;
  };
};
