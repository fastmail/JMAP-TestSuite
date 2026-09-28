use jmaptest;

# RFC 8621 S2: "name" is the only client-settable Mailbox property with no
# default, so a create without one must be rejected.  RFC 8620 S5.3 lets a
# method pick a more specific error than invalidProperties, so only the
# rejection is asserted.

attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  subtest "create with no name at all" => sub {
    my $res = $tester->request([[
      "Mailbox/set" => {
        create => { nameless => {} },
      },
    ]]);
    ok($res->is_success, "Mailbox/set does not fail as a whole")
      or diag explain $res->response_payload;

    my $args = $res->single_sentence("Mailbox/set")->arguments;

    ok(!$args->{created}{nameless}, 'the mailbox was not created');
    ok($args->{notCreated}{nameless}, 'reported in notCreated')
      or diag explain $args;

    my $err = $args->{notCreated}{nameless} || {};
    ok($err->{type}, 'the SetError has a type') or return;

    if ($err->{type} eq 'invalidProperties') {
      ok(grep { $_ eq 'name' } @{ $err->{properties} // [] },
         'properties names "name" as the problem')
        or diag explain $err;
    }
    else {
      note("server used a more specific error than invalidProperties: $err->{type}");
    }
  };

  subtest "create with an explicitly null name" => sub {
    my $res = $tester->request([[
      "Mailbox/set" => {
        create => { nullname => { name => undef } },
      },
    ]]);
    ok($res->is_success, "Mailbox/set does not fail as a whole");

    my $args = $res->single_sentence("Mailbox/set")->arguments;
    ok(!$args->{created}{nullname}, 'not created');
    ok($args->{notCreated}{nullname}, 'reported in notCreated')
      or diag explain $args;
  };

  subtest "create with an empty-string name" => sub {
    my $res = $tester->request([[
      "Mailbox/set" => {
        create => { emptyname => { name => '' } },
      },
    ]]);
    ok($res->is_success, "Mailbox/set does not fail as a whole");

    my $args = $res->single_sentence("Mailbox/set")->arguments;
    ok(!$args->{created}{emptyname}, 'not created');
    ok($args->{notCreated}{emptyname}, 'reported in notCreated')
      or diag explain $args;
  };

  subtest "a rejected create does not stop a good one in the same call" => sub {
    my $res = $tester->request([[
      "Mailbox/set" => {
        create => {
          bad  => {},
          good => { name => "Valid $^T.$$" },
        },
      },
    ]]);
    ok($res->is_success, "Mailbox/set with one bad and one good create");

    my $args = $res->single_sentence("Mailbox/set")->arguments;

    ok($args->{notCreated}{bad},  'the bad create is rejected');
    ok($args->{created}{good},    'the good create still succeeded')
      or diag explain $args;
    ok($args->{created}{good}{id}, 'and it has an id');
  };
};
