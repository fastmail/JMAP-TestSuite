use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $parent = $account->create_mailbox;
  my $other  = $account->create_mailbox;
  my $name   = "Sibling $^T.$$";
  my $first  = $parent->add_mailbox({ name => $name });

  # RFC 8621 S2: "There MUST NOT be two sibling Mailboxes with both the same
  # parent and the same name."  Mailbox/set defines no specific SetError for
  # this, so RFC 8620 S5.3 invalidProperties applies; the S5.4 alreadyExists
  # also fits.
  my $dup_error = any(
    invalid_properties('name'),
    superhashof({ type => 'alreadyExists' }),
  );

  subtest "create a duplicate sibling" => sub {
    my $res = $tester->request([[
      "Mailbox/set" => {
        create => { dup => { name => $name, parentId => $parent->id } },
      },
    ]]);
    ok($res->is_success, "Mailbox/set") or diag explain $res->response_payload;

    my $args = $res->single_sentence("Mailbox/set")->arguments;
    ok(!$args->{created}{dup}, "duplicate not created") or diag explain $args;
    jcmp_deeply($args->{notCreated}{dup}, $dup_error, "notCreated with a SetError")
      or diag explain $args;
  };

  subtest "create two same-named siblings in one call" => sub {
    my $name2 = "$name pair";
    my $res = $tester->request([[
      "Mailbox/set" => {
        create => {
          a => { name => $name2, parentId => $parent->id },
          b => { name => $name2, parentId => $parent->id },
        },
      },
    ]]);
    ok($res->is_success, "Mailbox/set") or diag explain $res->response_payload;

    my $args = $res->single_sentence("Mailbox/set")->arguments;
    my @created = grep { $args->{created}{$_} } qw(a b);
    ok(@created <= 1, "at most one of the pair created") or diag explain $args;
  };

  subtest "rename to an existing sibling's name" => sub {
    my $second = $parent->add_mailbox;

    my $res = $tester->request([[
      "Mailbox/set" => {
        update => { $second->id => { name => $name } },
      },
    ]]);
    ok($res->is_success, "Mailbox/set") or diag explain $res->response_payload;

    my $args = $res->single_sentence("Mailbox/set")->arguments;
    ok(!exists $args->{updated}{ $second->id }, "rename not applied")
      or diag explain $args;
    jcmp_deeply($args->{notUpdated}{ $second->id }, $dup_error, "notUpdated with a SetError")
      or diag explain $args;
  };

  subtest "move under a parent that has a same-named child" => sub {
    my $mover = $other->add_mailbox({ name => $name });

    my $res = $tester->request([[
      "Mailbox/set" => {
        update => { $mover->id => { parentId => $parent->id } },
      },
    ]]);
    ok($res->is_success, "Mailbox/set") or diag explain $res->response_payload;

    my $args = $res->single_sentence("Mailbox/set")->arguments;
    ok(!exists $args->{updated}{ $mover->id }, "move not applied")
      or diag explain $args;
    jcmp_deeply($args->{notUpdated}{ $mover->id }, $dup_error, "notUpdated with a SetError")
      or diag explain $args;
  };

  subtest "same name under a different parent is allowed" => sub {
    # Not under $other: the move subtest left a $name child there.
    my $aunt = $account->create_mailbox;

    my $res = $tester->request([[
      "Mailbox/set" => {
        create => { cousin => { name => $name, parentId => $aunt->id } },
      },
    ]]);
    ok($res->is_success, "Mailbox/set") or diag explain $res->response_payload;

    my $args = $res->single_sentence("Mailbox/set")->arguments;
    jcmp_deeply(
      $args->{created}{cousin},
      superhashof({ id => jstr }),
      "created a same-named Mailbox under another parent",
    ) or diag explain $args;
  };
};
