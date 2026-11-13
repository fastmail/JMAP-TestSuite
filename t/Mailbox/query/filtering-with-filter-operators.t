use jmaptest;

# We need to know that only our mailboxes here exist for predicting filter
# results, so we need a pristine account.
attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mailbox1 = $account->create_mailbox({
    name => 'aaa',
  });

  my $mailbox2 = $account->create_mailbox({
    parentId => $mailbox1->id,
    name => 'bbb',
  });

  my $res = $tester->request({
    methodCalls => [[
      "Mailbox/get" => {},
    ]],
  });

  my @mailboxes = @{
    $res->single_sentence("Mailbox/get")->arguments->{list}
  };

  my @with_roles = grep {; $_->{role} } @mailboxes;

  plan skip_all => "No mailboxes with roles found, can't continue"
    unless @with_roles;

  my %mailboxes_by_id = map {; $_->{id} => $_ } @mailboxes;

  my $describer_sub = $self->make_describer_sub(\%mailboxes_by_id);

  my @all_ids       = map {; $_->{id} } @mailboxes;
  my @with_role_ids = map {; $_->{id} } @with_roles;

  # AND
  $self->test_query(
    $account,
    "Mailbox/query",
    {
      filter => {
        operator => 'AND',
        conditions => [
          { hasAnyRole => JSON::false, },
          { parentId => undef, },
        ],
      },
      sort => [{ property => 'name', isAscending => JSON::true, }],
    },
    { ids => [ $mailbox1->id ], },
    $describer_sub,
    "AND - two conditions",
  );

  $self->test_query(
    $account,
    "Mailbox/query",
    {
      filter => {
        operator => 'AND',
        conditions => [
          { hasAnyRole => JSON::false, },
          { parentId => $mailbox1->id, },
        ],
      },
      sort => [{ property => 'name', isAscending => JSON::true, }],
    },
    { ids => [ $mailbox2->id ], },
    $describer_sub,
    "AND - two conditions",
  );

  $self->test_query(
    $account,
    "Mailbox/query",
    {
      filter => {
        operator => 'AND',
        conditions => [
          {
            operator => 'AND',
            conditions => [
              { hasAnyRole => JSON::false, },
              { parentId => $mailbox1->id, },
            ],
          },
        ],
      },
      sort => [{ property => 'name', isAscending => JSON::true, }],
    },
    { ids => [ $mailbox2->id ], },
    $describer_sub,
    "AND - two conditions nested one level deep",
  );

  # OR
  $self->test_query(
    $account,
    "Mailbox/query",
    {
      filter => {
        operator => 'OR',
        conditions => [
          { hasAnyRole => JSON::false, },
          { parentId => $mailbox1->id, },
        ],
      },
      sort => [{ property => 'name', isAscending => JSON::true, }],
    },
    { ids => [ $mailbox1->id, $mailbox2->id ], },
    $describer_sub,
    "OR - two conditions",
  );

  $self->test_unordered_query(
    $account,
    {
      operator => 'OR',
      conditions => [
        { hasAnyRole => JSON::true, },
        { hasAnyRole => JSON::true, },
      ],
    },
    \@with_role_ids,
    "OR - two conditions, same cond",
  );

  $self->test_unordered_query(
    $account,
    {
      operator => 'OR',
      conditions => [
        { hasAnyRole => JSON::true, },
        { hasAnyRole => JSON::false, },
      ],
    },
    \@all_ids,
    "OR - two conditions, diff conds",
  );

  # NOT
  $self->test_query(
    $account,
    "Mailbox/query",
    {
      filter => {
        operator => 'NOT',
        conditions => [
          { hasAnyRole => JSON::true, },
        ],
      },
      sort => [{ property => 'name', isAscending => JSON::true, }],
    },
    { ids => [ $mailbox1->id, $mailbox2->id ], },
    $describer_sub,
    "NOT - one condition",
  );

  $self->test_query(
    $account,
    "Mailbox/query",
    {
      filter => {
        operator => 'NOT',
        conditions => [
          { hasAnyRole => JSON::true, },
          { hasAnyRole => JSON::false, },
        ],
      },
      sort => [{ property => 'name', isAscending => JSON::true, }],
    },
    { ids => [ ], },
    $describer_sub,
    "NOT - two conditions",
  );
};

# RFC 8620 S5.5: the default collation is server dependent, so results that
# include server-provisioned Mailboxes are compared without regard to order.
sub test_unordered_query {
  my ($self, $account, $filter, $expect, $test) = @_;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my $res = $account->tester->request([[
    "Mailbox/query" => { filter => $filter },
  ]]);

  jcmp_deeply(
    $res->single_sentence("Mailbox/query")->arguments,
    superhashof({ ids => bag(@$expect) }),
    $test,
  ) or diag explain $res->as_stripped_triples;
}

sub make_describer_sub {
  my ($self, $mailboxes_by_id) = @_;

  return sub {
    my ($self, $id) = @_;

    return    $mailboxes_by_id->{$id}->{name}
           || $mailboxes_by_id->{$id}->name;
  }
}
