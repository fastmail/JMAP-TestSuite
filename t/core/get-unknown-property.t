use jmaptest;

# RFC 8620 S5.1: "If an invalid property is requested, the call MUST be
# rejected with an invalidArguments error."

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mailbox = $account->create_mailbox;

  for my $case (
    [ "only an unknown property",   [ "jmtsNoSuchProperty" ] ],
    [ "a known and an unknown one", [ "name", "jmtsNoSuchProperty" ] ],
  ) {
    my ($desc, $properties) = @$case;

    subtest $desc => sub {
      my $res = $tester->request([[
        "Mailbox/get" => { ids => [ $mailbox->id ], properties => $properties },
      ]]);
      ok($res->is_success, "the request completed")
        or return diag explain $res->response_payload;

      my $s = $res->single_sentence;
      is($s->name, "error", "Mailbox/get is rejected")
        or return diag explain $res->as_stripped_triples;
      jcmp_deeply(
        $s->arguments,
        superhashof({ type => "invalidArguments" }),
        "with invalidArguments",
      ) or diag explain $res->as_stripped_triples;
    };
  }
};
