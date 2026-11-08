use jmaptest;

# draft-ietf-jmap-filenode-20 (the draft) S3.2.5: every FileNode/query
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
  $n{a}   = $D->add_node({ name => 'a.txt', content => 'a' x 5,  mediaType => 'text/plain', $when->(2020) });
  $n{b}   = $D->add_node({ name => 'b.png', content => 'b' x 20, mediaType => 'image/png', $when->(2022),
                           executable => JSON::true });
  $n{sub} = $D->add_node({ name => 'sub', $when->(2021) });
  $n{c}   = $n{sub}->add_node({ name => 'c.txt', content => 'c' x 10, mediaType => 'text/plain', $when->(2023) });
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
    # draft S3.2.5 depth: "The maximum depth in the tree, counted from the
    # top level ... nodes with a null parentId are at depth 0 ... depth is
    # never counted from [parentId or ancestorId] ... If null, there is no
    # limit."  So D's children are at D's depth + 1, c at + 2.
    my $chain = $tester->request([[ 'FileNode/get' => { ids => [ $D->id ], fetchParents => JSON::true,
                                                        properties => [ 'parentId' ] } ]])
                       ->single_sentence('FileNode/get')->arguments->{list};
    my $dd = @$chain - 1;   # D's ancestors
    $is->({ ancestorId => $D->id }, [qw(a b sub)], "depth: only nodes within it", bare => 1, args => { depth => $dd + 1 });
    $is->({ ancestorId => $D->id }, [qw(a b sub c)], "one deeper takes c", bare => 1, args => { depth => $dd + 2 });
    $is->({ ancestorId => $D->id }, [], "depth is never counted from ancestorId", bare => 1, args => { depth => 1 })
      if $dd >= 1;
    $is->({ parentId => $D->id }, [qw(a b sub)], "parentId is exact, whatever depth", bare => 1, args => { depth => $dd + 5 });
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
    # draft S3.2.5 nodeType: "Only nodes whose @type is precisely this value"
    $is->({ nodeType => 'Directory' }, [qw(sub)], "nodeType Directory");
    $is->({ nodeType => 'File' }, [qw(a b c)], "nodeType File");
    # draft S3.2.5 role / hasAnyRole: none of these nodes has a role, and
    # they "match only nodes whose @type is Directory ... for both true and
    # false values"
    $is->({ role => 'trash' }, [], "role");
    $is->({ hasAnyRole => JSON::false }, [qw(sub)], "hasAnyRole false matches only Directories");
    $is->({ hasAnyRole => JSON::true }, [], "hasAnyRole true");
    # draft S3.2.5 isExecutable: "If true, the FileNode must have a true
    # executable value"
    $is->({ isExecutable => JSON::true }, [qw(b)], "isExecutable");
    $is->({ isExecutable => JSON::false }, [qw(a c)], "isExecutable false matches only Files");
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
    my $files = sub { +{ operator => 'AND', conditions => [ { nodeType => 'File' }, @_ ] } };
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
    # draft S3.2.5 mediaType: "exactly the same octets"; mediaTypeMatch: nameMatch's glob
    $is->({ mediaType => 'image/png' }, [qw(b)], "mediaType");
    $is->({ mediaTypeMatch => 'text/*' }, [qw(a c)], "mediaTypeMatch");
    # draft S3.2.5 text: body, or "if its name or mediaType contains this
    # value, compared case-insensitively"; the body half may match more, so
    # only what name or mediaType gives is required
    my $text = $q->({ text => 'IMAGE/P' });
    ok(grep({ $_ eq 'b' } @$text), "text matches a substring of mediaType") or diag explain $text;
    $text = $q->({ text => '.TXT' });
    ok(grep({ $_ eq 'a' } @$text) && grep({ $_ eq 'c' } @$text), "text matches a substring of name") or diag explain $text;
  };

  subtest "operators" => sub {
    # RFC 8620 S5.5: FilterOperator
    $is->({ operator => 'OR', conditions => [ { name => 'a.txt' }, { name => 'sub' } ] }, [qw(a sub)], "OR");
    $is->({ operator => 'NOT', conditions => [ { nodeType => 'File' } ] }, [qw(sub)], "NOT");
  };
};
