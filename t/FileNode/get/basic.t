use jmaptest;

# draft-ietf-jmap-filenode-15 (the draft): the capability objects, the
# FileNode object, and FileNode/get with fetchParents.
attr pristine => 1;

my $CAP = 'urn:ietf:params:jmap:filenode';

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities('urn:ietf:params:jmap:core', $CAP);

  my $session = fetch_session($tester) or return;

  subtest "capability objects" => sub {
    # draft S2.1: "The value of this property in the JMAP session
    # "capabilities" property MUST be an empty object."
    cmp_deeply($session->{capabilities}{$CAP}, {}, "session capability is an empty object");

    # draft S2.1: the account capability "MUST contain" these keys.  The
    # session resource is plain JSON (not typed), so the types are checked
    # by hand.
    my $bool = code(sub { JSON::is_bool($_[0]) || (0, "not a JSON boolean") });
    my $str  = code(sub { (defined $_[0] && !ref $_[0]) || (0, "not a string") });
    my $uint = re(qr/\A[0-9]+\z/);
    my $cap = $session->{accounts}{ $account->accountId }{accountCapabilities}{$CAP};
    cmp_deeply($cap, superhashof({
      maxFileNodeDepth          => any(undef, $uint),
      maxSizeFileNodeName       => $uint,
      forbiddenNameChars        => any(undef, $str),
      forbiddenNodeNames        => any(undef, array_each($str)),
      fileNodeQuerySortOptions  => array_each($str),
      mayCreateTopLevelFileNode => $bool,
      webTrashUrl               => any(undef, $str),
      caseInsensitiveNames      => $bool,
      webUrlTemplate            => any(undef, $str),
      webWriteUrlTemplate       => any(undef, $str),
    }), "account capability has every required key, with its type") or diag explain $cap;

    # draft S2.1 maxSizeFileNodeName: "This MUST be at least 100"
    cmp_ok($cap->{maxSizeFileNodeName}, '>=', 100, "maxSizeFileNodeName is at least 100");
  };

  # draft S3.1: the FileNode object's properties and their types
  my $rights = {
    map {; $_ => jbool() } qw(mayRead mayAddChildren mayRename mayDelete mayModifyContent mayShare)
  };
  my $node_shape = superhashof({
    id           => jstr(),
    parentId     => any(undef, jstr()),
    nodeType     => jstr(),
    blobId       => any(undef, jstr()),
    size         => any(undef, jnum()),
    name         => jstr(),
    type         => any(undef, jstr()),
    created      => jstr(),
    modified     => any(undef, jstr()),
    accessed     => any(undef, jstr()),
    changed      => jstr(),
    executable   => jbool(),
    isSubscribed => jbool(),
    myRights     => $rights,
    shareWith    => any(undef, hash_each($rights)),
    role         => any(undef, jstr()),
  });
  # draft S3.1 blobId/size/type: "MUST be null for directory" nodes, and
  # non-null for file nodes
  my $dir_shape  = superhashof({ nodeType => 'directory', blobId => undef, size => undef, type => undef });
  my $file_shape = superhashof({ nodeType => 'file', blobId => jstr(), size => jnum(), type => jstr() });

  subtest "FileNode/get of every top-level node" => sub {
    my $res = $tester->request([
      [ 'FileNode/query' => { filter => { isTopLevel => JSON::true } }, 'q' ],
      [ 'FileNode/get'   => { '#ids' => { resultOf => 'q', name => 'FileNode/query', path => '/ids' } }, 'g' ],
    ]);
    ok($res->is_success, "FileNode/query + FileNode/get") or diag explain $res->response_payload;
    my $args = $res->sentence(1)->arguments;
    ok(defined $args->{state}, "FileNode/get has a state");
    for my $n (@{ $args->{list} }) {
      jcmp_deeply($n, $node_shape, "top-level node $n->{id} has every property") or diag explain $n;
      # draft S3.2.5 isTopLevel: "the node must have a null parentId"
      is($n->{parentId}, undef, "top-level node $n->{id} has a null parentId");
      jcmp_deeply($n, $n->{nodeType} eq 'directory' ? $dir_shape : $file_shape,
                  "top-level node $n->{id}: blobId, size and type fit its nodeType")
        if $n->{nodeType} =~ /\A(?:file|directory)\z/;
    }
  };

  my $dir  = JMAP::TestSuite::Entity::FileNode->scratch_dir($account);
  my $sub  = $dir->add_node({ name => 'sub' });
  my $file = $sub->add_node({ name => 'hello.txt', content => "hello world", type => 'text/plain' });

  subtest "a file and a directory" => sub {
    my $res = $tester->request([[ 'FileNode/get' => { ids => [ $sub->id, $file->id ] } ]]);
    ok($res->is_success, "FileNode/get") or diag explain $res->response_payload;
    my %got = map {; $_->{id} => $_ } @{ $res->single_sentence('FileNode/get')->arguments->{list} };
    jcmp_deeply($got{ $sub->id }, all($node_shape, $dir_shape, superhashof({ name => 'sub', parentId => $dir->id })),
                "the directory") or diag explain \%got;
    # draft S3.1 size: "The size in bytes of the associated blob data"
    jcmp_deeply($got{ $file->id }, all($node_shape, $file_shape,
                superhashof({ name => 'hello.txt', parentId => $sub->id, size => 11, type => 'text/plain' })),
                "the file") or diag explain \%got;
  };

  subtest "fetchParents" => sub {
    # draft S3.2.1 fetchParents: "the server returns all ancestor nodes of
    # the requested ids in addition to the requested nodes themselves",
    # and an ancestor is not duplicated
    my $res = $tester->request([[ 'FileNode/get' => {
      ids => [ $file->id, $sub->id ], fetchParents => JSON::true, properties => [ 'parentId' ],
    } ]]);
    ok($res->is_success, "FileNode/get with fetchParents") or diag explain $res->response_payload;
    my @list = @{ $res->single_sentence('FileNode/get')->arguments->{list} };
    my %by_id = map {; $_->{id} => $_ } @list;
    is(scalar(keys %by_id), scalar(@list), "no node is listed twice") or diag explain \@list;
    ok($by_id{ $_ }, "the list holds $_") for $file->id, $sub->id, $dir->id;
    # every ancestor up to the top
    my $id = $file->id;
    my $hops = 0;
    while (defined $id && $by_id{$id} && $hops++ < 100) { $id = $by_id{$id}{parentId} }
    is($id, undef, "the parent chain is complete up to a top-level node") or diag explain \@list;

    my $plain = $tester->request([[ 'FileNode/get' => { ids => [ $file->id ], properties => [ 'parentId' ] } ]]);
    is(scalar @{ $plain->single_sentence('FileNode/get')->arguments->{list} }, 1,
       "without fetchParents (draft S3.2.1: default false) only the node itself");
  };

  subtest "unknown id" => sub {
    # RFC 8620 S5.1: ids that do not exist are in notFound
    my $res = $tester->request([[ 'FileNode/get' => { ids => [ 'nonexistent-filenode' ] } ]]);
    ok($res->is_success, "FileNode/get") or diag explain $res->response_payload;
    my $args = $res->single_sentence('FileNode/get')->arguments;
    jcmp_deeply($args->{notFound}, [ 'nonexistent-filenode' ], "notFound");
    jcmp_deeply($args->{list}, [], "empty list");
  };
};
