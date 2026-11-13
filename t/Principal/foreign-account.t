use jmaptest;

# Naming a real account outside this session must fail with accountNotFound
# (RFC 8620 §3.6.2), exactly as an unknown id does.

attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $other   = $self->pristine_account;

  # draft-ietf-jmap-calendars S1.5.2: Principal/getAvailability is only
  # available with its own capability in "using", so test it only where
  # advertised.
  my $avail = 'urn:ietf:params:jmap:principals:availability';
  my %advertised = map {; $_ => 1 } @{ $account->tester->default_using // [] };

  $account->tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:principals',
    grep { $advertised{$_} } $avail,
  );

  foreign_account_not_found_ok($account, $other, [
    [ 'Principal/get'             => { ids => [] } ],
    [ 'Principal/changes'         => { sinceState => '0' } ],
    [ 'Principal/query'           => {} ],
    [ 'Principal/queryChanges'    => { sinceQueryState => '0' } ],
    [ 'Principal/set'             => {} ],
    ($advertised{$avail}
      ? [ 'Principal/getAvailability' => { id => 'x',
                                           utcStart => '2025-07-01T00:00:00Z',
                                           utcEnd   => '2025-07-02T00:00:00Z' } ]
      : ()),
  ]);
};
