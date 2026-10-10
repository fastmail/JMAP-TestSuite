use jmaptest;

# draft-ietf-jmap-filenode-15 (the draft) S3.1 and S3.2.3: FileNode/set create.
attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities('urn:ietf:params:jmap:core', 'urn:ietf:params:jmap:filenode');

  my $cap = JMAP::TestSuite::Entity::FileNode->capability($account) or return;
  my $dir = JMAP::TestSuite::Entity::FileNode->scratch_dir($account);

  my $blob = $tester->upload({
    accountId => $account->accountId,
    type      => 'text/plain',
    blob      => \"twelve bytes",
  });

  my $create = sub {
    my ($create, $extra) = @_;
    my $res = $tester->request([[ 'FileNode/set' => { create => $create, %{ $extra || {} } } ]]);
    ok($res->is_success, "FileNode/set") or diag explain $res->response_payload;
    return $res->single_sentence('FileNode/set')->arguments;
  };

  subtest "a directory" => sub {
    # draft S3.1 nodeType: "If not provided on creation, the server infers
    # the type: ... "directory" otherwise"
    my $args = $create->({ d => { parentId => $dir->id, name => 'a directory' } });
    # RFC 8620 S5.3: created holds the id and every property the server set
    jcmp_deeply($args->{created}{d}, superhashof({ id => jstr() }), "created, with an id")
      or diag explain $args;
    my $id = $args->{created}{d}{id} or return;
    my $got = $tester->request([[ 'FileNode/get' => { ids => [ $id ] } ]])
                     ->single_sentence('FileNode/get')->arguments->{list}[0];
    # draft S3.1: blobId, size and type "MUST be null for directory" nodes
    jcmp_deeply($got, superhashof({
      nodeType => 'directory', parentId => $dir->id, name => 'a directory',
      blobId => undef, size => undef, type => undef,
    }), "inferred a directory") or diag explain $got;
  };

  subtest "a file" => sub {
    # draft S3.1 nodeType: inferred "file" if blobId is non-null; size is
    # server-set, so (RFC 8620 S5.3) it is in created
    my $args = $create->({ f => { parentId => $dir->id, name => 'a file.txt',
                                  blobId => $blob->blobId, type => 'text/plain' } });
    jcmp_deeply($args->{created}{f}, superhashof({ id => jstr(), size => jnum(12) }),
                "created, with the id and the server-set size") or diag explain $args;
    my $id = $args->{created}{f}{id} or return;
    my $got = $tester->request([[ 'FileNode/get' => { ids => [ $id ] } ]])
                     ->single_sentence('FileNode/get')->arguments->{list}[0];
    jcmp_deeply($got, superhashof({
      nodeType => 'file', parentId => $dir->id, name => 'a file.txt',
      blobId => jstr(), size => jnum(12), type => 'text/plain',
    }), "inferred a file") or diag explain $got;
  };

  subtest "a file without content" => sub {
    # draft S3.1 blobId: "Creating ... a file node to have a null blobId is
    # an "invalidProperties" error"
    my $args = $create->({ n => { parentId => $dir->id, name => 'no content', nodeType => 'file' } });
    jcmp_deeply($args->{notCreated}{n}, invalid_properties(), "invalidProperties") or diag explain $args;
  };

  subtest "names" => sub {
    # draft S3.1 name: "at least 1 character in length"; the server "MUST
    # reject names containing any character listed in forbiddenNameChars,
    # or matching any entry in forbiddenNodeNames (case-insensitively), with
    # an "invalidProperties" error"
    my %bad = (empty => '');
    my @chars = split //, ($cap->{forbiddenNameChars} // '');
    $bad{"char$_"} = "bad$chars[$_]name" for 0 .. $#chars;
    my @names = @{ $cap->{forbiddenNodeNames} || [] };
    $bad{"node$_"} = $names[$_] for 0 .. $#names;
    $bad{"nodeuc$_"} = uc $names[$_] for grep { uc $names[$_] ne $names[$_] } 0 .. $#names;
    # draft S2.1 maxSizeFileNodeName: "The maximum length, in (UTF-8) octets"
    $bad{toolong} = 'x' x ($cap->{maxSizeFileNodeName} + 1);

    my $args = $create->({ map {; $_ => { parentId => $dir->id, name => $bad{$_} } } keys %bad });
    for my $k (sort keys %bad) {
      jcmp_deeply($args->{notCreated}{$k}, invalid_properties('name'),
                  "name '" . substr($bad{$k}, 0, 20) . "' is invalidProperties") or diag explain $args->{notCreated}{$k};
    }
    ok(!%{ $args->{created} || {} }, "nothing created") or diag explain $args->{created};

    my $max = 'y' x $cap->{maxSizeFileNodeName};
    $args = $create->({ m => { parentId => $dir->id, name => $max } });
    ok($args->{created}{m}, "a name of exactly maxSizeFileNodeName octets is fine") or diag explain $args;
  };

  subtest "alreadyExists" => sub {
    my $first = $dir->add_node({ name => 'taken' });
    # draft S3.2.3 onExists: "If null, an attempt to create ... a FileNode
    # which would cause a name collision will be rejected by the server with
    # an "alreadyExists" error"; the SetError "MUST include an existingId"
    my $args = $create->({ t => { parentId => $dir->id, name => 'taken' } });
    jcmp_deeply($args->{notCreated}{t}, superhashof({ type => 'alreadyExists', existingId => $first->id }),
                "alreadyExists with existingId") or diag explain $args;

    # draft S3.1 name: "There MUST NOT be two sibling FileNodes with both the
    # same parent and the same name", so a pair in one call cannot both be
    # created
    $args = $create->({ p1 => { parentId => $dir->id, name => 'pair' }, p2 => { parentId => $dir->id, name => 'pair' } });
    is(scalar(grep { $args->{created}{$_} } qw(p1 p2)), 1, "exactly one of a same-named pair is created")
      or diag explain $args;
    my ($lost) = grep { !$args->{created}{$_} } qw(p1 p2);
    jcmp_deeply($args->{notCreated}{$lost}, superhashof({ type => 'alreadyExists' }), "the other is alreadyExists")
      if $lost;
  };

  subtest "a child created by reference" => sub {
    # RFC 8620 S5.3: a creation id may be referenced later in the same call
    my $args = $create->({
      outer => { parentId => $dir->id, name => 'outer' },
      inner => { parentId => '#outer', name => 'inner.txt', blobId => $blob->blobId, type => 'text/plain' },
    });
    ok($args->{created}{outer} && $args->{created}{inner}, "both created") or diag explain $args;
    my $got = $tester->request([[ 'FileNode/get' => { ids => [ $args->{created}{inner}{id} ], properties => [ 'parentId' ] } ]])
                     ->single_sentence('FileNode/get')->arguments->{list}[0];
    is($got->{parentId}, $args->{created}{outer}{id}, "the child is inside the directory");
  };

  subtest "top level" => sub {
    plan skip_all => "the account may create top-level nodes" if $cap->{mayCreateTopLevelFileNode};
    # draft S2.1 mayCreateTopLevelFileNode: only if true "the user may create
    # a FileNode ... with a null parentId"
    my $args = $create->({ top => { parentId => undef, name => "top $^T.$$" } });
    ok(!$args->{created}{top}, "not created") or diag explain $args;
    ok($args->{notCreated}{top}, "notCreated with a SetError") or diag explain $args;
  };
};
