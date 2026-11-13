use jmaptest;

# RFC 8621 S8: an account's one VacationResponse "MUST have the id
# 'singleton'".  Any other id names nothing, so an update of it is a notFound
# SetError (RFC 8620 S5.3); creating and destroying are basic.t's.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:vacationresponse',
  );

  my $res = $tester->request([[
    "VacationResponse/set" => {
      update => { nosuchvacation => { isEnabled => jfalse } },
    },
  ]]);
  ok($res->is_success, "VacationResponse/set does not fail as a whole")
    or diag explain $res->response_payload;

  my $args = $res->single_sentence("VacationResponse/set")->arguments;
  is($args->{notUpdated}{nosuchvacation}{type}, 'notFound',
     'an id other than singleton is notFound')
    or diag explain $args;
  ok(!exists $args->{updated}{nosuchvacation}, 'not reported as updated');
};
