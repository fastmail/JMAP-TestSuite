use jmaptest;

# We need to know that only our mailboxes here exist for predicting filter
# results, so we need a pristine account.
attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

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

  my @all_name_asc = map {;
    $_->{id}
  } sort {
    $a->{name} cmp $b->{name}
  } @mailboxes;

  my @with_role_name_asc = map {;
    $_->{id}
  } sort {
    $a->{name} cmp $b->{name}
  } @with_roles;

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

  $self->test_query(
    $account,
    "Mailbox/query",
    {
      filter => {
        operator => 'OR',
        conditions => [
          { hasAnyRole => JSON::true, },
          { hasAnyRole => JSON::true, },
        ],
      },
      sort => [{ property => 'name', isAscending => JSON::true, }],
    },
    { ids => [ @with_role_name_asc ], },
    $describer_sub,
    "OR - two conditions, same cond",
  );

  $self->test_query(
    $account,
    "Mailbox/query",
    {
      filter => {
        operator => 'OR',
        conditions => [
          { hasAnyRole => JSON::true, },
          { hasAnyRole => JSON::false, },
        ],
      },
      sort => [{ property => 'name', isAscending => JSON::true, }],
    },
    { ids => [ @all_name_asc ], },
    $describer_sub,
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

sub make_describer_sub {
  my ($self, $mailboxes_by_id) = @_;

  return sub {
    my ($self, $id) = @_;

    return    $mailboxes_by_id->{$id}->{name}
           || $mailboxes_by_id->{$id}->name;
  }
}
