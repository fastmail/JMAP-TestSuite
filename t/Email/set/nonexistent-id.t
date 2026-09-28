use jmaptest;

# RFC 8620 S5.3: an unknown id MUST be rejected with a notFound SetError, and
# the server MUST continue to the next id rather than terminating the method.

attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $missing = 'nosuchemail';

  subtest "update a non-existent email" => sub {
    my $res = $tester->request([[
      "Email/set" => {
        # Whole property, not a patch: a server validating patches before
        # resolving ids could answer invalidPatch instead of notFound.
        update => { $missing => { keywords => { '$seen' => \1 } } },
      },
    ]]);
    ok($res->is_success, "Email/set does not fail as a whole")
      or diag explain $res->response_payload;

    my $args = $res->single_sentence("Email/set")->arguments;

    is($args->{notUpdated}{$missing}{type}, 'notFound',
       'notUpdated carries a notFound SetError');
    ok(!exists $args->{updated}{$missing}, 'not reported as updated');
  };

  subtest "destroy a non-existent email" => sub {
    my $res = $tester->request([[
      "Email/set" => {
        destroy => [$missing],
      },
    ]]);
    ok($res->is_success, "Email/set does not fail as a whole")
      or diag explain $res->response_payload;

    my $args = $res->single_sentence("Email/set")->arguments;

    is($args->{notDestroyed}{$missing}{type}, 'notFound',
       'notDestroyed carries a notFound SetError');
    ok(!(grep { $_ eq $missing } @{ $args->{destroyed} // [] }),
       'not reported as destroyed');
  };

  subtest "a bad id does not stop a good one in the same call" => sub {
    my $mailbox = $account->create_mailbox;
    my $email   = $mailbox->add_message;

    my $res = $tester->request([[
      "Email/set" => {
        destroy => [$missing, $email->id],
      },
    ]]);
    ok($res->is_success, "Email/set with one bad and one good id");

    my $args = $res->single_sentence("Email/set")->arguments;

    is($args->{notDestroyed}{$missing}{type}, 'notFound',
       'the bad id is rejected');
    ok(grep { $_ eq $email->id } @{ $args->{destroyed} // [] },
       'the good id is still destroyed');
  };
};
