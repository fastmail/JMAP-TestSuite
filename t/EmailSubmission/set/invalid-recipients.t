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
          to         => [{ email => $from }],
          subject    => 'Test invalid recipients',
          keywords   => { '$draft' => jtrue() },
          mailboxIds => { $mailbox->id => jtrue() },
          bodyValues => { body => { value => 'Test body.' } },
          textBody   => [{ partId => 'body', type => 'text/plain' }],
        },
      },
    },
  ]])->single_sentence("Email/set")->arguments->{created}{draft}{id};
  ok(defined $email_id, "created a draft") or return;

  my $bad = 'not an address';

  my $res = $tester->request([[
    "EmailSubmission/set" => {
      create => {
        s1 => {
          emailId    => $email_id,
          identityId => $identity->{id},
          envelope   => {
            mailFrom => { email => $from },
            rcptTo   => [{ email => $from }, { email => $bad }],
          },
        },
      },
    },
  ]]);
  ok($res->is_success, "EmailSubmission/set") or diag explain $res->response_payload;

  my $args = $res->single_sentence("EmailSubmission/set")->arguments;
  ok(!$args->{created}{s1}, "submission not created") or diag explain $args;

  # RFC 8621 S7.5: for a rcptTo value "which is not a valid email address
  # for sending to", an "'invalidRecipients' 'String[]' property MUST also
  # be present on the SetError"; RFC 8620 S5.3 puts it ahead of
  # invalidProperties.
  jcmp_deeply(
    $args->{notCreated}{s1},
    superhashof({
      type              => 'invalidRecipients',
      invalidRecipients => [ $bad ],
    }),
    "notCreated with invalidRecipients listing the bad address",
  ) or diag explain $args;
};
