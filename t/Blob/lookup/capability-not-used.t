use jmaptest;

# RFC 9404 S4.3 and draft-ietf-jmap-blobext S6: if a type's "associated
# capability has not been requested", the result is an "unknownDataType"
# error.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my %advertised = map {; $_ => 1 } @{ $tester->default_using // [] };
  $tester->require_capabilities('urn:ietf:params:jmap:core');

  my @caps = grep {; $advertised{$_} } qw(urn:ietf:params:jmap:blob urn:ietf:params:jmap:blob2);
  plan skip_all => "server advertises neither blob capability" unless @caps;

  my $blob = $tester->upload({
    accountId => $account->accountId,
    type      => 'text/plain',
    blob      => \"lookup test",
  });

  for my $cap (@caps) {
    subtest "$cap without mail" => sub {
      my $res = $tester->request({
        using       => [ 'urn:ietf:params:jmap:core', $cap ],
        methodCalls => [[
          "Blob/lookup" => { typeNames => [ 'Email' ], ids => [ $blob->blobId ] },
        ]],
      });
      ok($res->is_success, "Blob/lookup") or diag(explain($res->response_payload)), return;

      jcmp_deeply(
        $res->single_sentence->as_stripped_pair,
        [ error => superhashof({ type => 'unknownDataType' }) ],
        "Email without urn:ietf:params:jmap:mail is unknownDataType",
      ) or diag explain $res->as_stripped_triples;
    };
  }
};
