use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $list = $tester->request([[
    "Mailbox/get" => { properties => [ 'role' ] },
  ]])->single_sentence("Mailbox/get")->arguments->{list};

  # RFC 8621 S2: "An account is not required to have Mailboxes with any
  # particular roles", so make one if there is none to collide with.
  my %by_role = map {; ($_->{role} // '') => $_->{id} } @$list;
  delete $by_role{''};
  my ($role) = grep { $by_role{$_} } qw(inbox trash drafts sent archive junk);
  ($role) = sort keys %by_role unless $role;
  my $own_role_mailbox;
  unless ($role) {
    $role = 'archive';
    $own_role_mailbox = $account->create_mailbox({ role => $role });
  }

  my $plain = $account->create_mailbox;
  my @stray;

  # RFC 8621 S2: "there MUST NOT be two Mailboxes in the same account with
  # the same role".  Mailbox/set names no SetError for this, so RFC 8620
  # S5.3 invalidProperties applies; the S5.4 alreadyExists also fits.
  my $dup_error = any(
    invalid_properties('role'),
    superhashof({ type => 'alreadyExists' }),
  );

  subtest "create a second Mailbox with role $role" => sub {
    my $res = $tester->request([[
      "Mailbox/set" => {
        create => { dup => { name => "Role dup $^T.$$", role => $role } },
      },
    ]]);
    ok($res->is_success, "Mailbox/set") or diag explain $res->response_payload;

    my $args = $res->single_sentence("Mailbox/set")->arguments;
    ok(!$args->{created}{dup}, "Mailbox not created") or diag explain $args;
    push @stray, $args->{created}{dup}{id} if $args->{created}{dup};
    jcmp_deeply($args->{notCreated}{dup}, $dup_error, "notCreated with a SetError")
      or diag explain $args;
  };

  subtest "give an existing Mailbox role $role" => sub {
    my $res = $tester->request([[
      "Mailbox/set" => {
        update => { $plain->id => { role => $role } },
      },
    ]]);
    ok($res->is_success, "Mailbox/set") or diag explain $res->response_payload;

    my $args = $res->single_sentence("Mailbox/set")->arguments;
    ok(!exists $args->{updated}{ $plain->id }, "update not applied")
      or diag explain $args;
    push @stray, $plain->id if exists $args->{updated}{ $plain->id };
    jcmp_deeply($args->{notUpdated}{ $plain->id }, $dup_error, "notUpdated with a SetError")
      or diag explain $args;
  };

  # RFC 8621 S2: role "MUST be one of the Mailbox attribute names listed in
  # the IANA 'IMAP Mailbox Name Attributes' registry".
  subtest "unregistered role" => sub {
    my $res = $tester->request([[
      "Mailbox/set" => {
        create => { bad => { name => "Bad role $^T.$$", role => 'x-jmap-testsuite-role' } },
      },
    ]]);
    ok($res->is_success, "Mailbox/set") or diag explain $res->response_payload;

    my $args = $res->single_sentence("Mailbox/set")->arguments;
    ok(!$args->{created}{bad}, "Mailbox not created") or diag explain $args;
    push @stray, $args->{created}{bad}{id} if $args->{created}{bad};
    jcmp_deeply(
      $args->{notCreated}{bad},
      invalid_properties('role'),
      "notCreated with invalidProperties",
    ) or diag explain $args;
  };

  # Don't leave a second role holder behind for other tests to trip over.
  push @stray, $own_role_mailbox->id if $own_role_mailbox;
  $tester->request([[ "Mailbox/set" => { destroy => \@stray } ]]) if @stray;
};
