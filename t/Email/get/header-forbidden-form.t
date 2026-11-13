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

  # RFC 8621 S4.2: fetching a parsed form that is forbidden for the header
  # field "MUST result in the method call being rejected with an
  # "invalidArguments" error"; S4.1.2 lists where each form may be used.
  for my $property (qw(
    header:From:asDate
    header:Date:asText
    header:Subject:asAddresses
    header:Subject:asGroupedAddresses
    header:From:asMessageIds
    header:Message-ID:asURLs
    header:List-Post:asAddresses
    header:References:asDate
    header:From:asDate:all
  )) {
    my $res = $tester->request([[
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [ 'id', $property ],
      },
    ]]);
    ok($res->is_success, "Email/get $property")
      or diag explain $res->response_payload;

    jcmp_deeply(
      $res->sentence(0)->as_stripped_pair,
      [ error => superhashof({ type => 'invalidArguments' }) ],
      "$property is rejected",
    ) or diag explain $res->as_stripped_triples;
  }
};
