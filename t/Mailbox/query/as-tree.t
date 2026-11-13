use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  # Every name carries a unique tag, so a name filter confines the query to
  # this test's Mailboxes.
  my $tag = "jmtstree$^T$$";

  my %mb;
  $mb{r}   = $account->create_mailbox({ name => "$tag keep r", sortOrder => 2 });
  $mb{r1}  = $mb{r}->add_mailbox({ name => "$tag keep r1", sortOrder => 1 });
  $mb{r2}  = $mb{r}->add_mailbox({ name => "$tag keep r2", sortOrder => 0 });
  $mb{s}   = $account->create_mailbox({ name => "$tag drop s", sortOrder => 1 });
  $mb{s1}  = $mb{s}->add_mailbox({ name => "$tag keep s1", sortOrder => 0 });
  $mb{s11} = $mb{s1}->add_mailbox({ name => "$tag keep s11", sortOrder => 0 });

  my %name_of = map {; $mb{$_}->id => $_ } keys %mb;
  my $ids = sub { [ map {; $mb{$_}->id } @_ ] };

  my $query = sub {
    my ($args, $want, $desc) = @_;

    my $res = $tester->request([[ "Mailbox/query" => $args ]]);
    ok($res->is_success, "Mailbox/query") or diag explain $res->response_payload;

    my $got = $res->single_sentence("Mailbox/query")->arguments->{ids};
    jcmp_deeply($got, $want, $desc)
      or diag explain [ map {; $name_of{$_} // $_ } @{ $got // [] } ];
  };

  my @sort = (
    { property => 'sortOrder', isAscending => JSON::true },
    { property => 'name',      isAscending => JSON::true },
  );

  subtest "sortAsTree" => sub {
    $query->(
      { filter => { name => $tag }, sort => \@sort },
      $ids->(qw(r2 s1 s11 s r1 r)),
      "without sortAsTree the comparators alone decide",
    );

    # RFC 8621 S2.3: an ancestor "always comes first regardless of the sort
    # comparators", and non-siblings compare by their sibling ancestors.
    $query->(
      { filter => { name => $tag }, sort => \@sort, sortAsTree => JSON::true },
      $ids->(qw(s s1 s11 r r2 r1)),
      "with sortAsTree the result is a depth-first walk of the tree",
    );
  };

  subtest "filterAsTree" => sub {
    $query->(
      { filter => { name => "$tag keep" }, sort => \@sort },
      bag(@{ $ids->(qw(r r1 r2 s1 s11)) }),
      "without filterAsTree every match is returned",
    );

    # RFC 8621 S2.3: "a Mailbox is only included in the query if all its
    # ancestors are also included in the query according to the filter."
    $query->(
      {
        filter       => { name => "$tag keep" },
        sort         => \@sort,
        filterAsTree => JSON::true,
      },
      bag(@{ $ids->(qw(r r1 r2)) }),
      "with filterAsTree descendants of a non-match are dropped",
    );
  };
};
