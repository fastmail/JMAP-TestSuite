use jmaptest;

# draft-ietf-jmap-filenode-15 (the draft) S3.2.5: the FileNode/query sort
# properties "tree", "nodeType" and "name".
attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities('urn:ietf:params:jmap:core', 'urn:ietf:params:jmap:filenode');

  my $cap = JMAP::TestSuite::Entity::FileNode->capability($account) or return;
  my %sortable = map {; $_ => 1 } @{ $cap->{fileNodeQuerySortOptions} || [] };

  #   D/ a.txt  b/ [ a/ [ y.txt ]  x.txt ]  c.txt  d/
  my $D = JMAP::TestSuite::Entity::FileNode->scratch_dir($account);
  my %n;
  $n{'c.txt'}   = $D->add_node({ name => 'c.txt', content => 'c' });
  $n{'b'}       = $D->add_node({ name => 'b' });
  $n{'a.txt'}   = $D->add_node({ name => 'a.txt', content => 'a' });
  $n{'d'}       = $D->add_node({ name => 'd' });
  $n{'b/x.txt'} = $n{b}->add_node({ name => 'x.txt', content => 'x' });
  $n{'b/a'}     = $n{b}->add_node({ name => 'a' });
  $n{'b/a/y.txt'} = $n{'b/a'}->add_node({ name => 'y.txt', content => 'y' });
  my %path_of = map {; $n{$_}->id => $_ } keys %n;

  my $q = sub {
    my ($sort) = @_;
    my $res = $tester->request([[ 'FileNode/query' => {
      filter => { ancestorId => $D->id }, sort => $sort,
    } ]]);
    ok($res->is_success, "FileNode/query") or diag explain $res->response_payload;
    return [ map {; $path_of{$_} // "?$_" } @{ $res->single_sentence('FileNode/query')->arguments->{ids} || [] } ];
  };

  subtest "tree" => sub {
    plan skip_all => "tree is not in fileNodeQuerySortOptions" unless $sortable{tree};
    # draft S3.2.5 tree: "Sort by tree; which means by name, but any
    # directory/collection node is immediately followed by the recursive
    # application of the same sort to its child nodes"
    is_deeply($q->([ { property => 'tree' } ]),
              [ 'a.txt', 'b', 'b/a', 'b/a/y.txt', 'b/x.txt', 'c.txt', 'd' ], "depth first, by name")
      or diag explain $q->([ { property => 'tree' } ]);
  };

  subtest "nodeType" => sub {
    plan skip_all => "nodeType is not in fileNodeQuerySortOptions" unless $sortable{nodeType};
    # draft S3.2.5 nodeType: "Directories sort first, then symlinks, then
    # files"
    my $got = $q->([ { property => 'nodeType' }, { property => 'name' } ]);
    my $first_file = (grep { $got->[$_] =~ /\.txt\z/ } 0 .. $#$got)[0];
    my $last_dir   = (grep { $got->[$_] !~ /\.txt\z/ } 0 .. $#$got)[-1];
    ok(defined $first_file && defined $last_dir && $last_dir < $first_file, "every directory before every file")
      or diag explain $got;
  };

  subtest "name" => sub {
    plan skip_all => "name is not in fileNodeQuerySortOptions" unless $sortable{name};
    # RFC 8620 S5.5: a sort on a property, with isAscending (default true)
    my @names = map {; m{([^/]+)\z} } @{ $q->([ { property => 'name' } ]) };
    is_deeply(\@names, [ sort @names ], "ascending by name") or diag explain \@names;
    my @desc = map {; m{([^/]+)\z} } @{ $q->([ { property => 'name', isAscending => JSON::false } ]) };
    is_deeply(\@desc, [ reverse sort @desc ], "descending by name") or diag explain \@desc;
  };
};
