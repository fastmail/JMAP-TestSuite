use jmaptest;

# Naming a real account outside this session must fail with accountNotFound
# (RFC 8620 §3.6.2), exactly as an unknown id does.

attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $other   = $self->pristine_account;

  $account->tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  foreign_account_not_found_ok($account, $other, [
    [ 'CalendarEvent/get'          => { ids => [] } ],
    [ 'CalendarEvent/changes'      => { sinceState => '0' } ],
    [ 'CalendarEvent/query'        => {} ],
    [ 'CalendarEvent/queryChanges' => { sinceQueryState => '0' } ],
    [ 'CalendarEvent/set'          => {} ],
    [ 'CalendarEvent/parse'        => { blobIds => [] } ],
    [ 'CalendarEvent/copy'         => { fromAccountId => 'SELF',  accountId => 'OTHER', create => {} } ],
    [ 'CalendarEvent/copy'         => { fromAccountId => 'OTHER', accountId => 'SELF',  create => {} } ],
  ]);
};
