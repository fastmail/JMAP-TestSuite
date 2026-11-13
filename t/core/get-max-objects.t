use jmaptest;

# RFC 8620 S5.1: a /get for more ids than the server will process may be
# rejected with requestTooLarge; maxObjectsInGet (S2) advertises that limit.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $session = fetch_session($tester) or return;
  my $max = $session->{capabilities}{'urn:ietf:params:jmap:core'}{maxObjectsInGet};
  ok(defined $max, "the session has maxObjectsInGet") or return;

  if ($max > 5000) {
    note("maxObjectsInGet is $max; too many ids to send cheaply");
    return;
  }

  my @ids = map {; "jmtsNoSuchMailbox$_" } 0 .. $max;

  my $res = $tester->request([[ "Mailbox/get" => { ids => \@ids } ]]);
  ok($res->is_success, "the request completed")
    or return diag explain $res->response_payload;

  my $s = $res->single_sentence;
  if ($s->name eq "error") {
    jcmp_deeply(
      $s->arguments,
      superhashof({ type => "requestTooLarge" }),
      "more than maxObjectsInGet ids is requestTooLarge",
    ) or diag explain $s->arguments;
  } else {
    # Rejecting is a "may"; a server that answers must answer correctly.
    is($s->name, "Mailbox/get", "got a Mailbox/get response");
    jcmp_deeply(
      $s->arguments->{notFound},
      bag(@ids),
      "every id is in notFound",
    ) or diag explain $s->arguments;
    note("server answered a /get for more than maxObjectsInGet ($max) ids");
  }
};
