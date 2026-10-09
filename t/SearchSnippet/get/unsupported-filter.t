use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $email = $account->create_mailbox->add_message({ subject => "snippet filter $$" });

  my $res = $tester->request([[
    "SearchSnippet/get" => {
      emailIds => [ $email->id ],
      filter   => { jmtsNoSuchCondition => 'x' },
    },
  ]]);
  ok($res->is_success, "SearchSnippet/get")
    or diag explain $res->response_payload;

  # RFC 8621 S5.1: "unsupportedFilter": "The server is unable to process the
  # given "filter" for any reason"; S4.4.1 defines no such condition, so
  # invalidArguments is a fair answer too.
  jcmp_deeply(
    $res->sentence(0)->as_stripped_pair,
    [ error => superhashof({ type => any(qw(unsupportedFilter invalidArguments)) }) ],
    "an unknown filter condition is rejected",
  ) or diag explain $res->as_stripped_triples;
};
