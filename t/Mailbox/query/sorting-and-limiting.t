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

  subtest "limits" => sub {
    subtest "Negative limit" => sub {
      my $res = $account->tester->request([[
        "Mailbox/query" => { limit => -5 },
      ]]);

      ok($res->is_success, "Mailbox/query")
        or diag explain $res->response_payload;

      jcmp_deeply(
        $res->sentence(0)->arguments,
        superhashof({
          type => 'invalidArguments',
          arguments => [ 'limit' ],
        }),
        "got invalidArguments for negative limit",
      ) or diag explain $res->as_stripped_triples;
    };
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
