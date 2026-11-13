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

  my @email_ids;
  my @sub_ids;
  for my $n (1, 2) {
    my $email_id = $tester->request([[
      "Email/set" => {
        create => {
          draft => {
            from       => [{ email => $from }],
            to         => [{ email => $from }],
            subject    => "Test EmailSubmission/query $n $^T.$$",
            keywords   => { '$draft' => jtrue() },
            mailboxIds => { $mailbox->id => jtrue() },
            bodyValues => { body => { value => 'Test body.' } },
            textBody   => [{ partId => 'body', type => 'text/plain' }],
          },
        },
      },
    ]])->single_sentence("Email/set")->arguments->{created}{draft}{id};
    ok(defined $email_id, "created draft $n") or return;

    my $set_args = $tester->request([[
      "EmailSubmission/set" => {
        create => { s => { emailId => $email_id, identityId => $identity->{id} } },
      },
    ]])->single_sentence("EmailSubmission/set")->arguments;
    plan skip_all => "server refused to send: forbiddenToSend"
      if ($set_args->{notCreated}{s}{type} // '') eq 'forbiddenToSend';
    ok($set_args->{created}{s}, "created submission $n") or diag explain $set_args;
    return unless $set_args->{created}{s};

    push @email_ids, $email_id;
    push @sub_ids,   $set_args->{created}{s}{id};
  }

  my $subs = $tester->request([[
    "EmailSubmission/get" => { ids => \@sub_ids },
  ]])->single_sentence("EmailSubmission/get")->arguments->{list};
  # RFC 8621 S7: the server "MAY destroy EmailSubmission objects at any
  # time after the message is successfully sent".
  plan skip_all => "submissions already destroyed" unless @$subs == 2;
  my ($s1) = grep { $_->{id} eq $sub_ids[0] } @$subs;

  my $query = sub {
    my ($args) = @_;
    my $res = $tester->request([[ "EmailSubmission/query" => $args ]]);
    return $res->single_sentence->arguments if $res->is_success
      && $res->single_sentence->name eq 'EmailSubmission/query';
    diag explain $res->as_stripped_triples;
    return { ids => undef };
  };
  my $ours = { emailIds => \@email_ids };

  # RFC 8621 S7.3: each FilterCondition property must match, and all of the
  # given ones must match together.
  subtest "filters" => sub {
    jcmp_deeply($query->({ filter => $ours })->{ids}, bag(@sub_ids), "emailIds");
    jcmp_deeply($query->({ filter => { emailIds => [ $email_ids[0] ] } })->{ids},
      [ $sub_ids[0] ], "emailIds with one id");
    jcmp_deeply($query->({ filter => { %$ours, identityIds => [ $identity->{id} ] } })->{ids},
      bag(@sub_ids), "identityIds matching");
    jcmp_deeply($query->({ filter => { %$ours, identityIds => [ 'no-such-identity' ] } })->{ids},
      [], "identityIds not matching");
    jcmp_deeply($query->({ filter => { %$ours, threadIds => [ $s1->{threadId} ] } })->{ids},
      [ $sub_ids[0] ], "threadIds");

    my $status = $s1->{undoStatus};
    my ($other) = grep { $_ ne $status } qw(pending final canceled);
    jcmp_deeply($query->({ filter => { emailIds => [ $email_ids[0] ], undoStatus => $status } })->{ids},
      [ $sub_ids[0] ], "undoStatus $status");
    jcmp_deeply($query->({ filter => { emailIds => [ $email_ids[0] ], undoStatus => $other } })->{ids},
      [], "undoStatus $other");

    # "before" excludes sendAt itself; "after" is "the same as or after".
    jcmp_deeply($query->({ filter => { emailIds => [ $email_ids[0] ], after => $s1->{sendAt} } })->{ids},
      [ $sub_ids[0] ], "after its own sendAt");
    jcmp_deeply($query->({ filter => { emailIds => [ $email_ids[0] ], before => $s1->{sendAt} } })->{ids},
      [], "before its own sendAt");
  };

  # RFC 8621 S7.3: "emailId", "threadId" and "sentAt" "MUST be supported for
  # sorting"; no EmailSubmission property is called sentAt, so its sendAt
  # is accepted in its place.
  for my $props ([ 'emailId' ], [ 'threadId' ], [ 'sentAt', 'sendAt' ]) {
    subtest "sort by $props->[0]" => sub {
      my ($asc, $desc);
      for my $prop (@$props) {
        $asc  = $query->({ filter => $ours, sort => [{ property => $prop }] })->{ids};
        $desc = $query->({
          filter => $ours,
          sort   => [{ property => $prop, isAscending => JSON::false }],
        })->{ids};
        last if $asc && $desc;
      }
      jcmp_deeply($asc,  bag(@sub_ids), "ascending sort accepted");
      jcmp_deeply($desc, bag(@sub_ids), "descending sort accepted");

      my %key = map {; $_->{id} => $_->{ $props->[0] =~ s/sentAt/sendAt/r } } @$subs;
      if ($asc && $desc && $key{ $sub_ids[0] } ne $key{ $sub_ids[1] }) {
        jcmp_deeply($desc, [ reverse @$asc ], "descending reverses ascending");
      }
    };
  }
};
