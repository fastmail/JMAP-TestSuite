use jmaptest;

# RFC 8620 S3.6.2: an unknown method name is an "unknownMethod" error response
# in place, not an HTTP error, and "Any further method calls in the request
# MUST then be processed as normal."

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities('urn:ietf:params:jmap:core');

  my $res = $tester->request([
    [ "Jmts/noSuchMethod" => {}, "c0" ],
    [ "Core/echo" => { accountId => \undef, hello => "world" }, "c1" ],
  ]);
  ok($res->is_success, "the request is not an HTTP error")
    or return diag explain $res->response_payload;

  jcmp_deeply(
    $res->as_stripped_triples,
    [
      [ "error", superhashof({ type => "unknownMethod" }), "c0" ],
      [ "Core/echo", { hello => "world" }, "c1" ],
    ],
    "unknownMethod for the first call, and the second still ran",
  ) or diag explain $res->as_stripped_triples;
};
