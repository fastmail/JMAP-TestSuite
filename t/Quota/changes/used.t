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

  my $get = sub {
    my $res = $tester->request([[ "Quota/get" => { ids => undef } ]]);
    ok($res->is_success, "Quota/get") or diag explain $res->response_payload;
    return $res->single_sentence("Quota/get")->arguments;
  };

  my $before = $get->();
  unless (@{ $before->{list} }) {
    pass("server reports no quotas for this account; nothing further to check");
    return;
  }

  $account->create_mailbox->add_message;

  my $after = $get->();
  my %used_before = map {; $_->{id} => $_->{used} } @{ $before->{list} };
  my @changed = grep {; defined $used_before{ $_->{id} } && $_->{used} != $used_before{ $_->{id} } }
                @{ $after->{list} };
  unless (@changed) {
    pass("adding a message changed no quota's usage; nothing further to check");
    return;
  }

  # RFC 8620 S5.2: the server "may choose how to divide up the changes".
  my ($state, @updated) = ($before->{state});
  for (1 .. 10) {
    my $res = $tester->request([[ "Quota/changes" => { sinceState => $state } ]]);
    ok($res->is_success, "Quota/changes") or diag(explain($res->response_payload)), return;

    my $s = $res->single_sentence;
    if ($s->name eq 'error' && ($s->arguments->{type} // '') eq 'cannotCalculateChanges') {
      pass("server cannot calculate changes from this state; RFC 8620 S5.2 permits this");
      return;
    }

    # RFC 9425 S4.3: updatedProperties is "String[]|null".
    jcmp_deeply(
      [ $s->name, $s->arguments ],
      [ 'Quota/changes', {
        accountId         => jstr($account->accountId),
        oldState          => jstr($state),
        newState          => ignore(),
        hasMoreChanges    => jbool,
        created           => array_each(jstr),
        updated           => array_each(jstr),
        destroyed         => array_each(jstr),
        updatedProperties => any(undef, array_each(jstr)),
      } ],
      "Quota/changes response looks right",
    ) or diag(explain($res->as_stripped_triples)), return;

    push @updated, @{ $s->arguments->{updated} };
    $state = $s->arguments->{newState};
    last unless $s->arguments->{hasMoreChanges};
  }

  jcmp_deeply(\@updated, superbagof(map {; jstr($_->{id}) } @changed), "changed quotas are reported updated")
    or diag explain \@updated;
};
