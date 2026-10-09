use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $email = $account->create_mailbox->add_message({ subject => "snippet ids $$" });

  my $unknown_id = 'jmts-no-such-email-' . time . '-' . $$;

  my $res = $tester->request([[
    "SearchSnippet/get" => {
      emailIds => [ $email->id, $unknown_id ],
      filter   => { text => "snippet" },
    },
  ]]);
  ok($res->is_success, "SearchSnippet/get")
    or diag explain $res->response_payload;

  # RFC 8621 S5.1: notFound is "An array of Email ids requested that could
  # not be found, or null if all ids were found".
  jcmp_deeply(
    $res->single_sentence("SearchSnippet/get")->arguments,
    {
      accountId => jstr($account->accountId),
      list      => [ {
        emailId => jstr($email->id),
        subject => any(undef, jstr()),
        preview => any(undef, jstr()),
      } ],
      notFound  => [ jstr($unknown_id) ],
    },
    "the unknown id is in notFound and has no snippet",
  ) or diag explain $res->as_stripped_triples;
};
