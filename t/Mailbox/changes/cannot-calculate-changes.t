use jmaptest;

# The Mailbox half of t/Email/changes/cannot-calculate-changes.t; see there.

attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $state = $tester->request([[
    "Mailbox/get" => { ids => [] },
  ]])->single_sentence("Mailbox/get")->arguments->{state};
  ok(defined $state, 'got a baseline Mailbox state');

  my $mailbox = $account->create_mailbox;

  subtest "changes from a recent, real state" => sub {
    my $res = $tester->request([[
      "Mailbox/changes" => { sinceState => $state },
    ]]);
    ok($res->is_success, "the request itself succeeded")
      or diag explain $res->response_payload;

    my $sent = $res->single_sentence;

    if ($sent->name eq 'error') {
      is($sent->arguments->{type}, 'cannotCalculateChanges',
         'the only acceptable error here is cannotCalculateChanges')
        or diag explain $sent->arguments;
      note("cannot calculate changes from a state issued moments ago: within spec, but inefficient");
      return;
    }

    is($sent->name, 'Mailbox/changes', 'got a Mailbox/changes response');

    my $args = $sent->arguments;
    ok(grep { $_ eq $mailbox->id } @{ $args->{created} // [] },
       'the new mailbox is reported as created')
      or diag explain $args;
    is($args->{oldState}, $state, 'oldState echoes what we asked from');
    isnt($args->{newState}, $state, 'newState has moved on');
  };

  subtest "a state that was never issued" => sub {
    my $res = $tester->request([[
      "Mailbox/changes" => { sinceState => 'bogus-state-xyz' },
    ]]);
    ok($res->is_success, "the request itself succeeded");

    my $sent = $res->single_sentence;
    is($sent->name, 'error', 'got an error response');
    is($sent->arguments->{type}, 'cannotCalculateChanges',
       'cannotCalculateChanges')
      or diag explain $sent->arguments;
  };
};
