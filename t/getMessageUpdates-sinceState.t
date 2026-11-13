use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  # RFC 8620 S3.6.2: an argument "of the wrong type" is invalidArguments,
  # a method-level error; the Request object itself is well-formed.
  my $res = $tester->request([[
    'Email/changes' => {
      sinceState => jnum(0),
    },
  ]]);

  ok($res->is_success, 'a bad argument is not a request-level error')
    or return diag explain $res->response_payload;

  jcmp_deeply(
    $res->single_sentence("error")->arguments,
    superhashof({
      type => 'invalidArguments',
    }),
    "non-string sinceState gives invalidArguments",
  ) or diag explain $res->as_stripped_triples;
};
