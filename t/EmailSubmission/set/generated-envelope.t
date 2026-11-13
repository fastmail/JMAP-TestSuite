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
          cc         => [{ email => $from }],
          bcc        => [{ email => $from }],
          subject    => 'Test generated envelope',
          keywords   => { '$draft' => jtrue() },
          mailboxIds => { $mailbox->id => jtrue() },
          bodyValues => { body => { value => 'Test body.' } },
          textBody   => [{ partId => 'body', type => 'text/plain' }],
        },
      },
    },
  ]])->single_sentence("Email/set")->arguments->{created}{draft}{id};
  ok(defined $email_id, "created a draft") or return;

  my $set_args = $tester->request([[
    "EmailSubmission/set" => {
      create => {
        s1 => { emailId => $email_id, identityId => $identity->{id}, envelope => undef },
      },
    },
  ]])->single_sentence("EmailSubmission/set")->arguments;

  plan skip_all => "server refused to send: forbiddenToSend"
    if ($set_args->{notCreated}{s1}{type} // '') eq 'forbiddenToSend';
  my $created = $set_args->{created}{s1};
  ok($created, "created a submission") or diag explain $set_args;
  return unless $created;

  my $envelope = $created->{envelope};
  unless ($envelope) {
    my $list = $tester->request([[
      "EmailSubmission/get" => { ids => [ $created->{id} ], properties => [ 'envelope' ] },
    ]])->single_sentence("EmailSubmission/get")->arguments->{list};
    # RFC 8621 S7: the server "MAY destroy EmailSubmission objects at any
    # time after the message is successfully sent".
    plan skip_all => "submission already destroyed" unless @$list;
    $envelope = $list->[0]{envelope};
  }

  # RFC 8621 S7: with a null envelope "the server MUST generate this from
  # the referenced Email": mailFrom from Sender/From, rcptTo "The
  # deduplicated set of email addresses from the To, Cc, and Bcc header
  # fields", with no parameters on any of them.
  my $address = superhashof({ email => $from });
  jcmp_deeply(
    $envelope,
    {
      mailFrom => $address,
      rcptTo   => [ $address ],
    },
    "envelope generated from From and the deduplicated To/Cc/Bcc",
  ) or diag explain $envelope;

  ok(
    !grep({ defined $_->{parameters} } $envelope->{mailFrom}, @{ $envelope->{rcptTo} // [] }),
    "no parameters were added",
  ) or diag explain $envelope;
};
