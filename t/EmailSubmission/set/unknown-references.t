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
          subject    => 'Test unknown references',
          keywords   => { '$draft' => jtrue() },
          mailboxIds => { $mailbox->id => jtrue() },
          bodyValues => { body => { value => 'Test body.' } },
          textBody   => [{ partId => 'body', type => 'text/plain' }],
        },
      },
    },
  ]])->single_sentence("Email/set")->arguments->{created}{draft}{id};
  ok(defined $email_id, "created a draft") or return;

  # RFC 8621 S7.5: "If the Email or Identity id given cannot be found, the
  # submission creation is rejected with a standard 'invalidProperties'
  # SetError."
  for my $case (
    [ emailId    => { emailId => 'no-such-email', identityId => $identity->{id} } ],
    [ identityId => { emailId => $email_id,       identityId => 'no-such-identity' } ],
  ) {
    my ($prop, $create) = @$case;

    subtest "unknown $prop" => sub {
      my $res = $tester->request([[
        "EmailSubmission/set" => {
          create => {
            s1 => {
              %$create,
              envelope => {
                mailFrom => { email => $from },
                rcptTo   => [{ email => $from }],
              },
            },
          },
        },
      ]]);
      ok($res->is_success, "EmailSubmission/set") or diag explain $res->response_payload;

      my $args = $res->single_sentence("EmailSubmission/set")->arguments;
      ok(!$args->{created}{s1}, "submission not created") or diag explain $args;
      jcmp_deeply(
        $args->{notCreated}{s1},
        invalid_properties($prop),
        "notCreated with invalidProperties",
      ) or diag explain $args;
    };
  }
};
