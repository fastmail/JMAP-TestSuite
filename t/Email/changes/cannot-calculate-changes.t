use jmaptest;

# RFC 8620 S5.2 makes 30 days of history only a SHOULD, so a fresh state may
# get a normal response or cannotCalculateChanges; a state that was never
# issued must get the error.

attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mailbox = $account->create_mailbox;

  my $state = $tester->request([[
    "Email/get" => { ids => [] },
  ]])->single_sentence("Email/get")->arguments->{state};
  ok(defined $state, 'got a baseline Email state');

  my $email = $mailbox->add_message;

  subtest "changes from a recent, real state" => sub {
    my $res = $tester->request([[
      "Email/changes" => { sinceState => $state },
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

    is($sent->name, 'Email/changes', 'got a Email/changes response');

    my $args = $sent->arguments;
    ok(grep { $_ eq $email->id } @{ $args->{created} // [] },
       'the new email is reported as created')
      or diag explain $args;
    is($args->{oldState}, $state, 'oldState echoes what we asked from');
    isnt($args->{newState}, $state, 'newState has moved on');
  };

  subtest "a state that was never issued" => sub {
    my $res = $tester->request([[
      "Email/changes" => { sinceState => 'bogus-state-xyz' },
    ]]);
    ok($res->is_success, "the request itself succeeded");

    my $sent = $res->single_sentence;
    is($sent->name, 'error', 'got an error response');
    is($sent->arguments->{type}, 'cannotCalculateChanges',
       'cannotCalculateChanges')
      or diag explain $sent->arguments;
  };
};
