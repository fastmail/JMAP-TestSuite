use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $email = $account->create_mailbox->add_message({ subject => "snippet null filter $$" });

  my $res = $tester->request([[
    "SearchSnippet/get" => {
      emailIds => [ $email->id ],
      filter   => undef,
    },
  ]]);
  ok($res->is_success, "SearchSnippet/get")
    or diag explain $res->response_payload;

  # RFC 8621 S5.1: filter is "FilterOperator|FilterCondition|null"; with no
  # text to match, S5 makes subject and preview null.
  jcmp_deeply(
    $res->sentence(0)->as_stripped_pair,
    [ 'SearchSnippet/get' => {
      accountId => $account->accountId,
      list      => [ { emailId => $email->id, subject => undef, preview => undef } ],
      notFound  => any(undef, []),
    } ],
    "a null filter gives a snippet with nothing highlighted",
  ) or diag explain $res->as_stripped_triples;
};
