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

  my $missing = 'nosuchmailbox';

  subtest "update a non-existent mailbox" => sub {
    my $res = $tester->request([[
      "Mailbox/set" => {
        update => { $missing => { name => 'does not matter' } },
      },
    ]]);
    ok($res->is_success, "Mailbox/set does not fail as a whole")
      or diag explain $res->response_payload;

    my $args = $res->single_sentence("Mailbox/set")->arguments;

    is($args->{notUpdated}{$missing}{type}, 'notFound',
       'notUpdated carries a notFound SetError');
    ok(!exists $args->{updated}{$missing}, 'not reported as updated');
  };

  subtest "destroy a non-existent mailbox" => sub {
    my $res = $tester->request([[
      "Mailbox/set" => {
        destroy => [$missing],
      },
    ]]);
    ok($res->is_success, "Mailbox/set does not fail as a whole")
      or diag explain $res->response_payload;

    my $args = $res->single_sentence("Mailbox/set")->arguments;

    is($args->{notDestroyed}{$missing}{type}, 'notFound',
       'notDestroyed carries a notFound SetError');
    ok(!(grep { $_ eq $missing } @{ $args->{destroyed} // [] }),
       'not reported as destroyed');
  };

  subtest "a bad id does not stop a good one in the same call" => sub {
    my $doomed = $account->create_mailbox;

    my $res = $tester->request([[
      "Mailbox/set" => {
        destroy => [$missing, $doomed->id],
      },
    ]]);
    ok($res->is_success, "Mailbox/set with one bad and one good id");

    my $args = $res->single_sentence("Mailbox/set")->arguments;

    is($args->{notDestroyed}{$missing}{type}, 'notFound',
       'the bad id is rejected');
    ok(grep { $_ eq $doomed->id } @{ $args->{destroyed} // [] },
       'the good id is still destroyed');
  };

};
