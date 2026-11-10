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
    'urn:ietf:params:jmap:calendars',
  );

  my $missing = 'nosuchevent';

  subtest "update a non-existent CalendarEvent" => sub {
    my $res = $tester->request([[
      "CalendarEvent/set" => {
        update => { $missing => { title => 'does not matter' } },
      },
    ]]);
    ok($res->is_success, "CalendarEvent/set does not fail as a whole")
      or diag explain $res->response_payload;

    my $args = $res->single_sentence("CalendarEvent/set")->arguments;

    is($args->{notUpdated}{$missing}{type}, 'notFound',
       'notUpdated carries a notFound SetError')
      or diag explain $args;
    ok(!exists $args->{updated}{$missing}, 'not reported as updated');
  };

  subtest "destroy a non-existent CalendarEvent" => sub {
    my $res = $tester->request([[
      "CalendarEvent/set" => {
        destroy => [$missing],
      },
    ]]);
    ok($res->is_success, "CalendarEvent/set does not fail as a whole")
      or diag explain $res->response_payload;

    my $args = $res->single_sentence("CalendarEvent/set")->arguments;

    is($args->{notDestroyed}{$missing}{type}, 'notFound',
       'notDestroyed carries a notFound SetError')
      or diag explain $args;
    ok(!(grep { $_ eq $missing } @{ $args->{destroyed} // [] }),
       'not reported as destroyed');
  };
};
