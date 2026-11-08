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
      supportedNodeTypes        => array_each($str),
      fileNodeQuerySortOptions  => array_each($str),
      mayCreateTopLevelFileNode => $bool,
      webTrashUrl               => any(undef, $str),
      caseInsensitiveNames      => $bool,
      webUrlTemplate            => any(undef, $str),
      webWriteUrlTemplate       => any(undef, $str),
    }), "account capability has every required key, with its type") or diag explain $cap;

    # draft-ietf-jmap-filenode-20 S2.1 supportedNodeTypes: "This MUST
    # include Directory and File"
    cmp_deeply($cap->{supportedNodeTypes}, superbagof(qw(Directory File)), "supportedNodeTypes has Directory and File");

    # draft S2.1 maxSizeFileNodeName: "This MUST be at least 100"
    cmp_ok($cap->{maxSizeFileNodeName}, '>=', 100, "maxSizeFileNodeName is at least 100");

    # draft S2.1 webUrlTemplate and webWriteUrlTemplate: "A URI Template
    # (level 1) ... The available variable is {id}" -- a client can expand
    # nothing else, so a template names {id} and no other variable
    for my $key (qw(webUrlTemplate webWriteUrlTemplate)) {
      next unless defined $cap->{$key};
      my @vars = $cap->{$key} =~ /\{([^}]*)\}/g;
      is_deeply([ sort @vars ], ['id'], "$key has {id} and no other variable") or diag $cap->{$key};
    }
  };

  # draft-ietf-jmap-filenode-20 S3.1: the FileNode object's properties and
  # their types.  "Properties that this document defines for one type MUST
  # NOT appear on a FileNode of another type; they are omitted rather than
  # set to null."
  my $rights = {
    map {; $_ => jbool() } qw(mayRead mayAddChildren mayRename mayDelete mayModifyContent mayShare)
  };
  my %common = (
    id       => jstr(),
    '@type'  => jstr(),
    parentId => any(undef, jstr()),
    name     => jstr(),
    created  => jstr(),
    modified => any(undef, jstr()),
    accessed => any(undef, jstr()),
    changed  => jstr(),
  );
  my %file_only = (blobId => jstr(), size => jnum(), mediaType => jstr(), executable => jbool());
  my %dir_only  = (isSubscribed => jbool(), myRights => $rights,
                   shareWith => any(undef, hash_each($rights)), role => any(undef, jstr()));
  my $dir_shape  = all(superhashof({ %common, %dir_only, '@type' => 'Directory' }),
                       code(sub { my @x = grep { exists $_[0]{$_} } keys %file_only, 'target';
                                  @x ? (0, "File properties on a Directory: @x") : 1 }));
  my $file_shape = all(superhashof({ %common, %file_only, '@type' => 'File' }),
                       code(sub { my @x = grep { exists $_[0]{$_} } keys %dir_only, 'target';
                                  @x ? (0, "Directory properties on a File: @x") : 1 }));
  my $node_shape = superhashof(\%common);

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
      jcmp_deeply($n, $n->{'@type'} eq 'Directory' ? $dir_shape : $file_shape,
                  "top-level node $n->{id}: its \@type's properties, and no others")
        if $n->{'@type'} =~ /\A(?:File|Directory)\z/;
    }
  };

  my $dir  = JMAP::TestSuite::Entity::FileNode->scratch_dir($account);
  my $sub  = $dir->add_node({ name => 'sub' });
  my $file = $sub->add_node({ name => 'hello.txt', content => "hello world", mediaType => 'text/plain' });

  subtest "a file and a directory" => sub {
    my $res = $tester->request([[ 'FileNode/get' => { ids => [ $sub->id, $file->id ] } ]]);
    ok($res->is_success, "FileNode/get") or diag explain $res->response_payload;
    my %got = map {; $_->{id} => $_ } @{ $res->single_sentence('FileNode/get')->arguments->{list} };
    jcmp_deeply($got{ $sub->id }, all($node_shape, $dir_shape, superhashof({ name => 'sub', parentId => $dir->id })),
                "the directory") or diag explain \%got;
    # draft S3.1 size: "The size in bytes of the associated blob data"
    jcmp_deeply($got{ $file->id }, all($node_shape, $file_shape,
                superhashof({ name => 'hello.txt', parentId => $sub->id, size => 11, mediaType => 'text/plain' })),
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
    # -20 S3.1.1: get "always returns \@type"
    is($plain->single_sentence('FileNode/get')->arguments->{list}[0]{'@type'}, 'File', "\@type is returned whatever properties asks for");
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
