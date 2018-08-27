use jmaptest;

# We need to know that only our mailboxes here exist for predicting filter
# results, so we need a pristine account.
attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;

  my %mailboxes = (
    zzz => $account->create_mailbox({
      name => "zzz", sortOrder => 1,
    }),
    xxx => $account->create_mailbox({
      name => "xxx", sortOrder => 2,
    }),
    yyy => $account->create_mailbox({
      name => "yyy", sortOrder => 3,
    }),
  );

  $mailboxes{bbb} = $account->create_mailbox({
    name => 'bbb', sortOrder => 4, parentId => $mailboxes{zzz}->id,
  });
  $mailboxes{aaa} = $account->create_mailbox({
    name => 'aaa', sortOrder => 5, parentId => $mailboxes{zzz}->id,
  });

  $mailboxes{ccc} = $account->create_mailbox({
    name => 'ccc', sortOrder => 6, parentId => $mailboxes{xxx}->id,
  });

  $mailboxes{ddd} = $account->create_mailbox({
    name => 'ddd', sortOrder => 7, parentId => $mailboxes{yyy}->id,
  });

  my %mailboxes_by_id = map {; $_->id => $_ } values %mailboxes;

  my @name_asc = map {; $_->id } @mailboxes{qw(
    aaa bbb ccc ddd xxx yyy zzz
  )};
  my @name_desc = reverse @name_asc;

  my @sort_order_asc = map {; $_->id } @mailboxes{qw(
    zzz xxx yyy bbb aaa ccc ddd
  )};
  my @sort_order_desc = reverse @sort_order_asc;

  my @parent_name_asc = map {; $_->id } @mailboxes{qw(
    xxx
      ccc
    yyy
      ddd
    zzz
      aaa
      bbb
  )};
  my @parent_name_desc = reverse @parent_name_asc;

  my $describer_sub = $self->make_describer_sub(\%mailboxes_by_id);

  # name
  $self->test_query(
    $account,
    "Mailbox/query",
    { sort => [{ property => 'name', }], },
    { ids => \@name_asc, },
    $describer_sub,
    "sort by name, implicit ascending order (default)",
  );

  $self->test_query(
    $account,
    "Mailbox/query",
    { sort => [{ property => 'name', isAscending => JSON::true, }], },
    { ids => \@name_asc, },
    $describer_sub,
    "sort by name, explicit ascending order",
  );

  $self->test_query(
    $account,
    "Mailbox/query",
    { sort => [{ property => 'name', isAscending => JSON::false, }], },
    { ids => \@name_desc, },
    $describer_sub,
    "sort by name, explicit descending order",
  );

  # sortOrder
  $self->test_query(
    $account,
    "Mailbox/query",
    { sort => [{ property => 'sortOrder', }], },
    { ids => \@sort_order_asc, },
    $describer_sub,
    "sort by sortOrder, implict ascending order"
  );

  $self->test_query(
    $account,
    "Mailbox/query",
    { sort => [{ property => 'sortOrder', isAscending => JSON::true, }], },
    { ids => \@sort_order_asc, },
    $describer_sub,
    "sort by sortOrder, explicit ascending order"
  );

  $self->test_query(
    $account,
    "Mailbox/query",
    { sort => [{ property => 'sortOrder', isAscending => JSON::false, }], },
    { ids => \@sort_order_desc, },
    $describer_sub,
    "sort by sortOrder, explicit descending order"
  );

  # parent/name
  $self->test_query(
    $account,
    "Mailbox/query",
    { sort => [{ property => 'parent/name', }], },
    { ids => \@parent_name_asc, },
    $describer_sub,
    "sort by parent/name, implict ascending order"
  );

  $self->test_query(
    $account,
    "Mailbox/query",
    { sort => [{ property => 'parent/name', isAscending => JSON::true, }], },
    { ids => \@parent_name_asc, },
    $describer_sub,
    "sort by parent/name, explicit ascending order"
  );

  $self->test_query(
    $account,
    "Mailbox/query",
    { sort => [{ property => 'parent/name', isAscending => JSON::false, }], },
    { ids => \@parent_name_desc, },
    $describer_sub,
    "sort by parent/name, explicit descending order"
  );

  # position 0, explicit
  $self->test_query(
    $account,
    "Mailbox/query",
    {
      sort => [{ property => 'parent/name', isAscending => JSON::true, }],
      position => 0,
    },
    { ids => \@parent_name_asc, },
    $describer_sub,
    "sort by parent/name, explicit ascending order, explicit position 0"
  );

  # negative positions start at end of list
  $self->test_query(
    $account,
    "Mailbox/query",
    {
      sort => [{ property => 'parent/name', isAscending => JSON::true, }],
      position => -1,
    },
    { ids => [ $parent_name_asc[-1] ], position => $#parent_name_asc, },
    $describer_sub,
    "sort by parent/name, explicit ascending order, explicit position -1"
  );

  $self->test_query(
    $account,
    "Mailbox/query",
    {
      sort => [{ property => 'parent/name', isAscending => JSON::true, }],
      position => -3,
    },
    { ids => [ @parent_name_asc[-3..-1] ], position => $#parent_name_asc - 2, },
    $describer_sub,
    "sort by parent/name, explicit ascending order, explicit position -3"
  );

  # positive positions start at beginning
  $self->test_query(
    $account,
    "Mailbox/query",
    {
      sort => [{ property => 'parent/name', isAscending => JSON::true, }],
      position => 1,
    },
    { ids => [ @parent_name_asc[1..$#parent_name_asc] ], position => 1, },
    $describer_sub,
    "sort by parent/name, explicit ascending order, explicit position 1"
  );

  $self->test_query(
    $account,
    "Mailbox/query",
    {
      sort => [{ property => 'parent/name', isAscending => JSON::true, }],
      position => 3,
    },
    { ids => [ @parent_name_asc[3..$#parent_name_asc] ], position => 3, },
    $describer_sub,
    "sort by parent/name, explicit ascending order, explicit position 3"
  );

  # position > total = no results
  $self->test_query(
    $account,
    "Mailbox/query",
    {
      sort => [{ property => 'parent/name', isAscending => JSON::true, }],
      position => $#parent_name_asc + 5,
    },
    { ids => [], position => 0, },
    $describer_sub,
    "sort by parent/name, explicit ascending order, explicit position too high"
  );

  # negative position too low clamped to 0
  $self->test_query(
    $account,
    "Mailbox/query",
    {
      sort => [{ property => 'parent/name', isAscending => JSON::true, }],
      position => $#parent_name_asc - ($#parent_name_asc + 10),
    },
    { ids => \@parent_name_asc, position => 0, },
    $describer_sub,
    "sort by parent/name, explicit ascending order, explicit position too low"
  );

  subtest "limits" => sub {
    subtest "Negative limit" => sub {
      my $res = $account->tester->request([[
        "Mailbox/query" => { limit => -5 },
      ]]);

      ok($res->is_success, "Mailbox/query")
        or diag explain $res->http_response->as_string;

      jcmp_deeply(
        $res->sentence(0)->arguments,
        superhashof({
          type => 'invalidArguments',
          arguments => [ 'limit' ],
        }),
        "got invalidArguments for negative limit",
      ) or diag explain $res->as_stripped_triples;
    };

    $self->test_query(
      $account,
      "Mailbox/query",
      {
        sort  => [{ property => 'parent/name', isAscending => JSON::true, }],
        limit => @parent_name_asc + 5,
      },
      { ids => \@parent_name_asc, total => 0+@parent_name_asc, },
      $describer_sub,
      "limit > total returns total"
    );

    $self->test_query(
      $account,
      "Mailbox/query",
      {
        sort  => [{ property => 'parent/name', isAscending => JSON::true, }],
        limit => 0 + @parent_name_asc,
      },
      { ids => \@parent_name_asc, total => 0+@parent_name_asc, },
      $describer_sub,
      "limit == total returns total"
    );

    $self->test_query(
      $account,
      "Mailbox/query",
      {
        sort  => [{ property => 'parent/name', isAscending => JSON::true, }],
        limit => @parent_name_asc - 2,
      },
      {
        ids => [ @parent_name_asc[0..($#parent_name_asc - 2)] ],
        total => 0+@parent_name_asc,
      },
      $describer_sub,
      "limit < total returns limit"
    );

    $self->test_query(
      $account,
      "Mailbox/query",
      {
        sort  => [{ property => 'parent/name', isAscending => JSON::true, }],
        limit => 0,
      },
      {
        ids => [ ],
        total => 0+@parent_name_asc,
      },
      $describer_sub,
      "limit 0 returns none"
    );
  };
};

sub make_describer_sub {
  my ($self, $mailboxes_by_id) = @_;

  return sub {
    my ($self, $id) = @_;

    return    $mailboxes_by_id->{$id}->{name}
           || $mailboxes_by_id->{$id}->name;
  }
}
