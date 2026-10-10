use jmaptest;

# draft-ietf-jmap-filenode-15 (the draft) S3.2.5: every FileNode/query
# filter condition, and depth.
attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities('urn:ietf:params:jmap:core', 'urn:ietf:params:jmap:filenode');

  my $D = JMAP::TestSuite::Entity::FileNode->scratch_dir($account);
  my %dates = map {; $_ => "$_-01-01T00:00:00Z" } 2020 .. 2023;
  my $when = sub { my $d = $dates{ $_[0] }; return (created => $d, modified => $d, accessed => $d) };

  my %n;
  $n{a}   = $D->add_node({ name => 'a.txt', content => 'a' x 5,  type => 'text/plain', $when->(2020) });
  $n{b}   = $D->add_node({ name => 'b.png', content => 'b' x 20, type => 'image/png',  $when->(2022),
                           executable => JSON::true });
  $n{sub} = $D->add_node({ name => 'sub', $when->(2021) });
  $n{c}   = $n{sub}->add_node({ name => 'c.txt', content => 'c' x 10, type => 'text/plain', $when->(2023) });
  my %name_of = map {; $n{$_}->id => $_ } keys %n;

  # The nodes of this test a query matches, by short name.  Unless asked
  # not to, the filter is ANDed with ancestorId (this test's directory), so
  # anything else in the account is left out.
  my $q = sub {
    my ($filter, %o) = @_;
    my $f = $o{bare} ? $filter
          : { operator => 'AND', conditions => [ { ancestorId => $D->id }, $filter ] };
    my $res = $tester->request([[ 'FileNode/query' => { filter => $f, %{ $o{args} || {} } } ]]);
    ok($res->is_success, "FileNode/query") or diag explain $res->response_payload;
    my $args = $res->single_sentence('FileNode/query')->arguments;
    return $o{ids} ? $args->{ids} : [ sort map {; $name_of{$_} // () } @{ $args->{ids} || [] } ];
  };
  my $is = sub {
    my ($filter, $want, $desc, %o) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    is_deeply($q->($filter, %o), [ sort @$want ], $desc) or diag explain $filter;
  };

  subtest "tree position" => sub {
    # draft S3.2.5 parentId: "A node must have a parentId equal to this"
    $is->({ parentId => $D->id }, [qw(a b sub)], "parentId", bare => 1);
    # draft S3.2.5 depth: "The number of levels of subdirectories to recurse
    # into.  If absent, null, or zero, do not recurse."  Recursion only means
    # something relative to a parentId condition (ancestorId is recursive
    # already), so depth 1 adds the children of parentId's subdirectories.
    # The draft could say outright that depth widens parentId.
    $is->({ parentId => $D->id }, [qw(a b sub c)], "parentId with depth 1", bare => 1, args => { depth => 1 });
    $is->({ parentId => $D->id }, [qw(a b sub)], "parentId with depth 0", bare => 1, args => { depth => 0 });
    # draft S3.2.5 ancestorId: "an ancestor (parent, parent of parent, etc.)"
    $is->({ ancestorId => $D->id }, [qw(a b sub c)], "ancestorId", bare => 1);
    $is->({ ancestorId => $n{sub}->id }, [qw(c)], "ancestorId of the subdirectory", bare => 1);

    # draft S3.2.5 descendantId: "A node must be an ancestor ... of the
    # node with this id"
    my $ids = $q->({ descendantId => $n{c}->id }, bare => 1, ids => 1);
    my %got = map {; $_ => 1 } @$ids;
    ok($got{ $n{sub}->id } && $got{ $D->id }, "descendantId: the parent and the grandparent") or diag explain $ids;
    ok(!grep({ $got{ $n{$_}->id } } qw(a b c)), "descendantId: not the node itself, nor any node off its parent chain")
      or diag explain $ids;

    # draft S3.2.5 isTopLevel: "the node must have a null parentId"
    my $top = $q->({ isTopLevel => JSON::true }, bare => 1, ids => 1);
    ok(@$top, "isTopLevel: some node is at the top");
    my $list = $tester->request([[ 'FileNode/get' => { ids => $top, properties => [ 'parentId' ] } ]])
                      ->single_sentence('FileNode/get')->arguments->{list};
    ok(!grep({ defined $_->{parentId} } @$list), "isTopLevel: every match has a null parentId") or diag explain $list;
    my $chain = $tester->request([[ 'FileNode/get' => { ids => [ $D->id ], fetchParents => JSON::true,
                                                        properties => [ 'parentId' ] } ]])
                       ->single_sentence('FileNode/get')->arguments->{list};
    my ($root) = grep { !defined $_->{parentId} } @$chain;
    ok($root && grep({ $_ eq $root->{id} } @$top), "isTopLevel: this test's top-level ancestor matches");
  };

  subtest "node type and role" => sub {
    # draft S3.2.5 nodeType: "Only nodes with precisely this nodeType"
    $is->({ nodeType => 'directory' }, [qw(sub)], "nodeType directory");
    $is->({ nodeType => 'file' }, [qw(a b c)], "nodeType file");
    # draft S3.2.5 role / hasAnyRole: none of these nodes has a role
    $is->({ role => 'trash' }, [], "role");
    $is->({ hasAnyRole => JSON::false }, [qw(a b sub c)], "hasAnyRole false");
    $is->({ hasAnyRole => JSON::true }, [], "hasAnyRole true");
    # draft S3.2.5 isExecutable: "If true, the FileNode must have a true
    # executable value"
    $is->({ isExecutable => JSON::true }, [qw(b)], "isExecutable");
    # draft S3.2.5 blobId: "A FileNode must have a blobId equal to this"
    $is->({ blobId => $n{a}->blobId }, [qw(a)], "blobId");
  };

  subtest "dates" => sub {
    # draft S3.2.5: *Before is "before this date"; *After is "on or after"
    for my $p (qw(created modified accessed)) {
      $is->({ "${p}Before" => $dates{2021} }, [qw(a)], "${p}Before is strict");
      $is->({ "${p}Before" => '2021-01-01T00:00:01Z' }, [qw(a sub)], "${p}Before");
      $is->({ "${p}After" => $dates{2022} }, [qw(b c)], "${p}After includes the date itself");
    }
  };

  subtest "sizes" => sub {
    my $files = sub { +{ operator => 'AND', conditions => [ { nodeType => 'file' }, @_ ] } };
    # draft S3.2.5 minSize: "equal to or greater than"; maxSize: "less than"
    $is->($files->({ minSize => 10 }), [qw(b c)], "minSize");
    $is->($files->({ maxSize => 10 }), [qw(a)], "maxSize");
    $is->($files->({ minSize => 5, maxSize => 20 }), [qw(a c)], "minSize and maxSize");
  };

  subtest "names and types" => sub {
    # draft S3.2.5 name: "exactly the same octets"
    $is->({ name => 'a.txt' }, [qw(a)], "name");
    $is->({ name => 'A.TXT' }, [], "name is exact");
    # draft S3.2.5 nameMatch: glob syntax, "The match is case-insensitive"
    $is->({ nameMatch => '*.TXT' }, [qw(a c)], "nameMatch * (case-insensitive)");
    $is->({ nameMatch => 'b.p?g' }, [qw(b)], "nameMatch ?");
    $is->({ nameMatch => '[ab].*' }, [qw(a b)], "nameMatch [set]");
    $is->({ nameMatch => '[a-b]*' }, [qw(a b)], "nameMatch [range]");
    $is->({ nameMatch => '[!a]*.*' }, [qw(b c)], "nameMatch [!set]");
    $is->({ nameMatch => '[^a]*.*' }, [qw(b c)], "nameMatch [^set]");
    $is->({ nameMatch => 'a' }, [], "nameMatch matches the whole name");
    # draft S3.2.5 type: "exactly the same octets"; typeMatch: nameMatch's glob
    $is->({ type => 'image/png' }, [qw(b)], "type");
    $is->({ typeMatch => 'text/*' }, [qw(a c)], "typeMatch");
    # draft S3.2.5 text: "equivalent to body OR nameMatch OR typeMatch"; the
    # body half may match more, so only what nameMatch or typeMatch gives is
    # required
    my $text = $q->({ text => 'image/png' });
    ok(grep({ $_ eq 'b' } @$text), "text matches through typeMatch") or diag explain $text;
    $text = $q->({ text => '*.txt' });
    ok(grep({ $_ eq 'a' } @$text) && grep({ $_ eq 'c' } @$text), "text matches through nameMatch") or diag explain $text;
  };

  subtest "operators" => sub {
    # RFC 8620 S5.5: FilterOperator
    $is->({ operator => 'OR', conditions => [ { name => 'a.txt' }, { name => 'sub' } ] }, [qw(a sub)], "OR");
    $is->({ operator => 'NOT', conditions => [ { nodeType => 'file' } ] }, [qw(sub)], "NOT");
  };
};
