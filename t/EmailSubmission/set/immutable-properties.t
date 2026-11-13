use jmaptest;

# RFC 8621 S7: identityId, emailId and envelope are "(immutable)", so once a
# submission exists an update changing any of them is rejected with an
# invalidProperties SetError naming it (RFC 8620 S5.3).  Each is changed to a
# different value: setting an immutable property to the value it already has
# is not a change.

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
  my $draft = sub {
    my ($subject) = @_;
    return $tester->request([[
      "Email/set" => {
        create => {
          d => {
            from       => [{ email => $from }],
            to         => [{ email => $from }],
            subject    => $subject,
            keywords   => { '$draft' => jtrue() },
            mailboxIds => { $mailbox->id => jtrue() },
            bodyValues => { body => { value => 'Test body.' } },
            textBody   => [{ partId => 'body', type => 'text/plain' }],
          },
        },
      },
    ]])->single_sentence("Email/set")->arguments->{created}{d}{id};
  };

  my $email_id = $draft->("immutable properties $$");
  my $other_id = $draft->("another draft $$");
  ok(defined $email_id && defined $other_id, "created two drafts") or return;

  my $set_args = $tester->request([[
    "EmailSubmission/set" => {
      create => { s1 => { emailId => $email_id, identityId => $identity->{id} } },
    },
  ]])->single_sentence("EmailSubmission/set")->arguments;
  plan skip_all => "server refused to send: forbiddenToSend"
    if ((($set_args->{notCreated} // {})->{s1} // {})->{type} // '') eq 'forbiddenToSend';
  # read without autovivifying: the diagnostics below show $set_args, and a
  # created.s1 that was never sent misled once
  my $sub_id = (($set_args->{created} // {})->{s1} // {})->{id};
  ok(defined $sub_id, "created a submission") or return diag explain $set_args;

  # RFC 8621 S7: a server "MAY destroy EmailSubmission objects at any time
  # after the message is successfully sent".
  my $exists = $tester->request([[
    "EmailSubmission/get" => { ids => [ $sub_id ], properties => [ 'id' ] },
  ]])->single_sentence("EmailSubmission/get")->arguments->{list}[0];
  plan skip_all => "the submission is already gone" unless $exists;

  for my $change (
    [ identityId => 'nosuchidentity' ],
    [ emailId    => $other_id ],
    [ envelope   => {
        mailFrom => { email => $from },
        rcptTo   => [ { email => "elsewhere$$\@example.com" } ],
      } ],
  ) {
    my ($prop, $value) = @$change;
    subtest "changing $prop" => sub {
      my $args = $tester->request([[
        "EmailSubmission/set" => { update => { $sub_id => { $prop => $value } } },
      ]])->single_sentence("EmailSubmission/set")->arguments;

      jcmp_deeply(
        $args->{notUpdated}{$sub_id},
        superhashof({ type => 'invalidProperties', properties => supersetof($prop) }),
        "rejected: invalidProperties naming $prop",
      ) or diag explain $args;
      ok(!exists $args->{updated}{$sub_id}, "not updated");
    };
  }
};
