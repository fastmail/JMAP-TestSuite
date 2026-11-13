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

  my $mailbox = $account->create_mailbox;

  my $email_id = $tester->request([[
    "Email/set" => {
      create => {
        draft => {
          from       => [{ email => $from }],
          subject    => 'Test no recipients',
          keywords   => { '$draft' => jtrue() },
          mailboxIds => { $mailbox->id => jtrue() },
          bodyValues => { body => { value => 'Test body.' } },
          textBody   => [{ partId => 'body', type => 'text/plain' }],
        },
      },
    },
  ]])->single_sentence("Email/set")->arguments->{created}{draft}{id};
  ok(defined $email_id, "created a draft without To, Cc or Bcc") or return;

  # RFC 8621 S7.5: noRecipients is for when "The envelope (supplied or
  # generated) does not have any rcptTo email addresses."
  for my $case (
    [ "generated envelope" => undef ],
    [ "supplied envelope"  => { mailFrom => { email => $from }, rcptTo => [] } ],
  ) {
    my ($desc, $envelope) = @$case;

    subtest $desc => sub {
      my $res = $tester->request([[
        "EmailSubmission/set" => {
          create => {
            s1 => {
              emailId    => $email_id,
              identityId => $identity->{id},
              envelope   => $envelope,
            },
          },
        },
      ]]);
      ok($res->is_success, "EmailSubmission/set") or diag explain $res->response_payload;

      my $args = $res->single_sentence("EmailSubmission/set")->arguments;
      ok(!$args->{created}{s1}, "submission not created") or diag explain $args;
      jcmp_deeply(
        $args->{notCreated}{s1},
        superhashof({ type => 'noRecipients' }),
        "notCreated with noRecipients",
      ) or diag explain $args;
    };
  }
};
