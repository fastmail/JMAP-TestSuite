use jmaptest;

test {
  my ($self) = @_;

  # We should be able to pass junk (like an integer sinceState instead of a
  # string sinceState like the spec requires) and get back a sensible JSON
  # blob telling us what we did wrong.
  my $res = $self->any_account->tester->request([[
    'Email/queryChanges' => {
      # JMAP expects this state value to be a string, so this call may be
      # rejected, but it shouldn't cause a server error.
      sinceState => jnum(0),
    },
  ]]);

  ok($res->is_success, 'called getMessageUpdates')
    or diag explain $res->http_response->as_string;
};
