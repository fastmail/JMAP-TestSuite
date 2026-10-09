use jmaptest;

# RFC 8620 S1.8: the server "MUST only follow the specifications that are
# opted into and behave as though it does not implement anything else", so a
# method from a capability not in "using" is unknownMethod.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $res = $tester->request({
    using       => [ 'urn:ietf:params:jmap:core' ],
    methodCalls => [
      [ "Mailbox/get" => { ids => [] }, "c0" ],
      [ "Core/echo" => { accountId => \undef, hello => "world" }, "c1" ],
    ],
  });
  ok($res->is_success, "the request is not an HTTP error")
    or return diag explain $res->response_payload;

  jcmp_deeply(
    $res->as_stripped_triples,
    [
      [ "error", superhashof({ type => "unknownMethod" }), "c0" ],
      [ "Core/echo", { hello => "world" }, "c1" ],
    ],
    "Mailbox/get without urn:ietf:params:jmap:mail is unknownMethod",
  ) or diag explain $res->as_stripped_triples;
};
