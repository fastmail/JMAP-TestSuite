use jmaptest;

attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
    'urn:ietf:params:jmap:quota',
  );

  my $res = $tester->request([[ "Quota/get" => { ids => undef } ]]);
  ok($res->is_success, "Quota/get") or diag explain $res->response_payload;

  my @list = @{ $res->single_sentence("Quota/get")->arguments->{list} };
  unless (@list) {
    pass("server reports no quotas for this account; nothing further to check");
    return;
  }

  # RFC 9425 S3.1 and S3.2 give the only values of Scope and ResourceType.
  for my $q (@list) {
    jcmp_deeply(
      $q,
      superhashof({
        resourceType => any(qw(count octets)),
        scope        => any(qw(account domain global)),
      }),
      "quota $q->{id} has a defined resourceType and scope",
    ) or diag explain $q;
  }
};
