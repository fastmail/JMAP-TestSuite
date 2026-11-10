use jmaptest;

# RFC 8621 S6: an Identity's email is the "From" address a client MUST use
# with it, and has no default.  A create without it is rejected: with
# invalidProperties naming email, or -- a server need not let clients create
# identities at all (S6.3) -- with forbidden or forbiddenFrom.  A server that
# creates it anyway must give it an address.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:submission',
  );

  my $args = $tester->request([[
    "Identity/set" => { create => { i => { name => "No address $$" } } },
  ]])->single_sentence("Identity/set")->arguments;

  if (my $err = $args->{notCreated}{i}) {
    if (($err->{type} // '') eq 'invalidProperties') {
      jcmp_deeply($err->{properties}, supersetof('email'), "rejected: invalidProperties naming email")
        or diag explain $err;
    } else {
      jcmp_deeply($err->{type}, any(qw(forbidden forbiddenFrom)),
        "rejected: identities cannot be created here") or diag explain $err;
    }
    return;
  }

  my $id = $args->{created}{i}{id};
  ok($id, "created instead") or return diag explain $args;
  my $identity = $tester->request([[
    "Identity/get" => { ids => [ $id ], properties => [ 'email' ] },
  ]])->single_sentence("Identity/get")->arguments->{list}[0];
  ok($identity && length($identity->{email} // ''), "then it has an address")
    or diag explain $identity;
  $tester->request([[ "Identity/set" => { destroy => [ $id ] } ]]);
};
