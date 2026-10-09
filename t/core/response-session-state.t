use jmaptest;

# RFC 8620 S3.4: a Response has "sessionState", "The current value of the
# state string on the Session object".

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities('urn:ietf:params:jmap:core');

  my $session = fetch_session($tester) or return;

  my $res = $tester->request([[ "Core/echo" => { accountId => \undef } ]]);
  ok($res->is_success, "Core/echo") or return diag explain $res->response_payload;

  jcmp_deeply(
    $res->wrapper_properties,
    superhashof({ sessionState => jstr($session->{state}) }),
    "the Response has the Session's state as sessionState",
  ) or diag explain { session_state => $session->{state}, response => $res->wrapper_properties };
};
