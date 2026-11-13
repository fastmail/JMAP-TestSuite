use jmaptest;

# RFC 8620 S5.2: maxChanges "MUST be a positive integer greater than 0", and
# the server "MUST reject the call with an invalidArguments error" otherwise.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $state = $account->get_state('mailbox');
  ok(defined $state, "got a Mailbox state");

  for my $case ([ "maxChanges 0", 0 ], [ "maxChanges -1", -1 ]) {
    my ($desc, $max) = @$case;

    subtest $desc => sub {
      my $res = $tester->request([[
        "Mailbox/changes" => { sinceState => $state, maxChanges => $max },
      ]]);
      ok($res->is_success, "the request completed")
        or return diag explain $res->response_payload;

      my $s = $res->single_sentence;
      is($s->name, "error", "Mailbox/changes is rejected")
        or return diag explain $res->as_stripped_triples;
      jcmp_deeply(
        $s->arguments,
        superhashof({ type => "invalidArguments" }),
        "with invalidArguments",
      ) or diag explain $res->as_stripped_triples;
    };
  }
};
