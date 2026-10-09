use jmaptest;

# RFC 8620 S3.7: a reference fails if the response to resultOf is not named
# "name", so a reference to a call that returned an error must fail.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $res = $tester->request([
    [ "Mailbox/get" => { accountId => "nonexistent-account-$^T-$$" }, "t0" ],
    [ "Mailbox/get" => {
        "#ids" => { resultOf => "t0", name => "Mailbox/get", path => "/list/*/id" },
      }, "t1" ],
  ]);
  ok($res->is_success, "the request completed")
    or return diag explain $res->response_payload;

  is($res->sentence(0)->name, "error", "the referenced call failed")
    or return diag explain $res->as_stripped_triples;

  is($res->sentence(1)->name, "error", "the referring call is an error");
  jcmp_deeply(
    $res->sentence(1)->arguments,
    superhashof({ type => "invalidResultReference" }),
    "a reference to an error response is invalidResultReference",
  ) or diag explain $res->as_stripped_triples;
};
