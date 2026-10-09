use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mailbox = $account->create_mailbox;
  $mailbox->add_message;

  # RFC 8621 S4.4.2: these sorts "MUST also have a "keyword" property", so
  # it is invalidArguments (RFC 8620 S3.6.2), or unsupportedSort if unknown.
  for my $property (qw(hasKeyword allInThreadHaveKeyword someInThreadHaveKeyword)) {
    my $res = $tester->request([[
      "Email/query" => {
        filter => { inMailbox => $mailbox->id },
        sort   => [ { property => $property } ],
      },
    ]]);
    ok($res->is_success, "Email/query sorting on $property")
      or diag explain $res->response_payload;

    jcmp_deeply(
      $res->sentence(0)->as_stripped_pair,
      [ error => superhashof({ type => any(qw(invalidArguments unsupportedSort)) }) ],
      "$property without a keyword is rejected",
    ) or diag explain $res->as_stripped_triples;
  }
};
