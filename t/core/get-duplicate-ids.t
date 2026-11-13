use jmaptest;

# RFC 8620 S5.1: "If an identical id is included more than once in the
# request, the server MUST only include it once in either the list or the
# notFound argument of the response."

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mailbox = $account->create_mailbox;
  my $missing = "jmtsNoSuchMailbox$$";

  my $res = $tester->request([[
    "Mailbox/get" => {
      ids        => [ $mailbox->id, $missing, $mailbox->id, $missing ],
      properties => [ "name" ],
    },
  ]]);
  ok($res->is_success, "Mailbox/get completed")
    or return diag explain $res->response_payload;

  jcmp_deeply(
    $res->single_sentence("Mailbox/get")->arguments,
    {
      accountId => jstr($account->accountId),
      state     => jstr,
      list      => [ { id => jstr($mailbox->id), name => jstr($mailbox->name) } ],
      notFound  => [ jstr($missing) ],
    },
    "each id appears exactly once, in list or in notFound",
  ) or diag explain $res->as_stripped_triples;
};
