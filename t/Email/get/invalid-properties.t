use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $message = $account->create_mailbox->add_message;

  # RFC 8620 S5.1: "If an invalid property is requested, the call MUST be
  # rejected with an "invalidArguments" error".  RFC 8621 S4.2 does not say
  # the same of bodyProperties, so those are not tested here.
  for my $test (
    [ properties     => [ 'id', 'jmtsNoSuchProperty' ] ],
    [ properties     => [ 'id', 'header:From:asNoSuchForm' ] ],
  ) {
    my ($arg, $list) = @$test;

    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [ 'id', 'textBody' ],
        $arg       => $list,
      },
    ]]);
    ok($res->is_success, "Email/get with $arg @$list")
      or diag explain $res->response_payload;

    jcmp_deeply(
      $res->sentence(0)->as_stripped_pair,
      [ error => superhashof({ type => 'invalidArguments' }) ],
      "$arg $list->[1] is rejected",
    ) or diag explain $res->as_stripped_triples;
  }
};
