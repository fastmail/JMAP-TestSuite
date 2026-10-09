use jmaptest;

# Naming a real account outside this session must fail with accountNotFound
# (RFC 8620 §3.6.2), exactly as an unknown id does.

attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $other   = $self->pristine_account;

  # draft-ietf-jmap-calendars S1.5.3: CalendarEvent/parse is only available
  # with its own capability in "using", so test it only where advertised.
  my $parse = 'urn:ietf:params:jmap:calendars:parse';
  my %advertised = map {; $_ => 1 } @{ $account->tester->default_using // [] };

  $account->tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
    grep { $advertised{$_} } $parse,
  );

  foreign_account_not_found_ok($account, $other, [
    [ 'CalendarEvent/get'          => { ids => [] } ],
    [ 'CalendarEvent/changes'      => { sinceState => '0' } ],
    [ 'CalendarEvent/query'        => {} ],
    [ 'CalendarEvent/queryChanges' => { sinceQueryState => '0' } ],
    [ 'CalendarEvent/set'          => {} ],
    ($advertised{$parse} ? [ 'CalendarEvent/parse' => { blobIds => [] } ] : ()),
    [ 'CalendarEvent/copy'         => { fromAccountId => 'SELF',  accountId => 'OTHER', create => {} } ],
    [ 'CalendarEvent/copy'         => { fromAccountId => 'OTHER', accountId => 'SELF',  create => {} } ],
  ]);
};
