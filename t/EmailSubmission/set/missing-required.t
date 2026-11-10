use jmaptest;

# RFC 8621 S7: emailId and identityId have no default -- a submission is of
# one Email, as one Identity -- so a create without either is rejected with
# an invalidProperties SetError naming it (RFC 8620 S5.3).  Neither create
# can send anything.

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

  my $mailbox  = $account->create_mailbox;
  my $email_id = $tester->request([[
    "Email/set" => {
      create => {
        d => {
          from       => [{ email => $from }],
          to         => [{ email => $from }],
          subject    => "missing required $$",
          keywords   => { '$draft' => jtrue() },
          mailboxIds => { $mailbox->id => jtrue() },
          bodyValues => { body => { value => 'Test body.' } },
          textBody   => [{ partId => 'body', type => 'text/plain' }],
        },
      },
    },
  ]])->single_sentence("Email/set")->arguments->{created}{d}{id};
  ok(defined $email_id, "created a draft") or return;

  for my $case (
    [ emailId    => { identityId => $identity->{id} } ],
    [ identityId => { emailId    => $email_id } ],
  ) {
    my ($missing, $create) = @$case;
    subtest "without $missing" => sub {
      my $args = $tester->request([[
        "EmailSubmission/set" => { create => { s => $create } },
      ]])->single_sentence("EmailSubmission/set")->arguments;

      jcmp_deeply(
        $args->{notCreated}{s},
        superhashof({ type => 'invalidProperties', properties => supersetof($missing) }),
        "rejected: invalidProperties naming $missing",
      ) or diag explain $args;
      ok(!exists $args->{created}{s}, "not created");
    };
  }
};
