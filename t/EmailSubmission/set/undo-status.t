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
          subject    => 'Test undoStatus',
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
      create => { s1 => { emailId => $email_id, identityId => $identity->{id} } },
    },
  ]])->single_sentence("EmailSubmission/set")->arguments;

  my $sub_id = $set_args->{created}{s1}{id};
  plan skip_all => "server refused to send: forbiddenToSend"
    if ($set_args->{notCreated}{s1}{type} // '') eq 'forbiddenToSend';
  ok(defined $sub_id, "created a submission") or diag explain $set_args;
  return unless defined $sub_id;

  my $get_args = $tester->request([[
    "EmailSubmission/get" => { ids => [ $sub_id ], properties => [ 'undoStatus' ] },
  ]])->single_sentence("EmailSubmission/get")->arguments;

  # RFC 8621 S7: a server "MAY destroy EmailSubmission objects at any time
  # after the message is successfully sent".
  my $submission = $get_args->{list}[0];
  plan skip_all => "submission already destroyed" unless $submission;

  # RFC 8621 S7: undoStatus "is server set on create and MUST be one of"
  # pending, final or canceled.
  jcmp_deeply(
    $submission->{undoStatus},
    any(qw(pending final canceled)),
    "undoStatus is pending, final or canceled",
  ) or diag explain $get_args;

  return note("undoStatus is $submission->{undoStatus}; not trying to cancel")
    unless $submission->{undoStatus} eq 'pending';

  my $res = $tester->request([[
    "EmailSubmission/set" => {
      update => { $sub_id => { undoStatus => 'canceled' } },
    },
  ]]);
  my $args = $res->single_sentence("EmailSubmission/set")->arguments;

  # RFC 8621 S7.5: a pending submission that "cannot be unsent" is refused
  # with cannotUnsend; otherwise the update succeeds and it is canceled.
  if (exists $args->{updated}{$sub_id}) {
    $tester->request_ok(
      [ "EmailSubmission/get" => { ids => [ $sub_id ], properties => [ 'undoStatus' ] } ],
      superhashof({
        list => any([], [ superhashof({ undoStatus => 'canceled' }) ]),
      }),
      "canceled submission reads back as canceled, or is gone",
    );
  } else {
    jcmp_deeply(
      $args->{notUpdated}{$sub_id},
      superhashof({ type => 'cannotUnsend' }),
      "cancel refused with cannotUnsend",
    ) or diag explain $args;
  }
};
