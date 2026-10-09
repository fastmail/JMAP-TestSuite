use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:submission',
  );

  my ($existing) = @{
    $tester->request([[ "Identity/get" => {} ]])
      ->single_sentence("Identity/get")->arguments->{list} // []
  };
  plan skip_all => "account has no identity" unless $existing;

  # Work on an identity of our own when the server lets us make one, and put
  # a pre-existing one back if the server wrongly changes it.
  my $created = $tester->request([[
    "Identity/set" => {
      create => { new1 => { email => $existing->{email}, name => 'Test Immutable' } },
    },
  ]])->single_sentence("Identity/set")->arguments->{created}{new1};
  my $id   = $created ? $created->{id} : $existing->{id};
  my $orig = $existing->{email};
  (my $new_email = $orig) =~ s/\A[^@]*/jmts-changed/;

  my $res = $tester->request([[
    "Identity/set" => { update => { $id => { email => $new_email } } },
  ]]);
  ok($res->is_success, "Identity/set") or diag explain $res->response_payload;

  my $args = $res->single_sentence("Identity/set")->arguments;

  # RFC 8621 S6: email is "(immutable)", which RFC 8620 S1.1 defines as
  # "The value MUST NOT change after the object is created."
  ok(!exists $args->{updated}{$id}, "update not applied") or diag explain $args;
  jcmp_deeply(
    $args->{notUpdated}{$id},
    invalid_properties('email'),
    "notUpdated with invalidProperties",
  ) or diag explain $args;

  my $after = $tester->request([[
    "Identity/get" => { ids => [ $id ], properties => [ 'email' ] },
  ]])->single_sentence("Identity/get")->arguments->{list}[0];
  is($after->{email}, $orig, "email unchanged");

  if ($created) {
    $tester->request([[ "Identity/set" => { destroy => [ $id ] } ]]);
  } elsif (($after->{email} // '') ne $orig) {
    $tester->request([[ "Identity/set" => { update => { $id => { email => $orig } } } ]]);
  }
};
