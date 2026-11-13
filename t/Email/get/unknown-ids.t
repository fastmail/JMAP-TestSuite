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

  my $unknown_id = 'jmts-no-such-email-' . time . '-' . $$;

  my $res = $tester->request([[
    "Email/get" => {
      ids        => [ $message->id, $unknown_id ],
      properties => [ 'threadId' ],
    },
  ]]);
  ok($res->is_success, "Email/get")
    or diag explain $res->response_payload;

  # RFC 8620 S5.1: notFound "contains the ids passed to the method for
  # records that do not exist".
  jcmp_deeply(
    $res->single_sentence("Email/get")->arguments,
    {
      accountId => jstr($account->accountId),
      state     => jstr(),
      list      => [ { id => jstr($message->id), threadId => jstr($message->threadId) } ],
      notFound  => [ jstr($unknown_id) ],
    },
    "unknown id is in notFound, known one in list",
  ) or diag explain $res->as_stripped_triples;
};
