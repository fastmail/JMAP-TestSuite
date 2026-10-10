use jmaptest;

# draft-ietf-jmap-filenode-15 (the draft) S3.1 and S3.2.3: FileNode/set
# update -- rename, move, cycles, immutable nodeType, content.
attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities('urn:ietf:params:jmap:core', 'urn:ietf:params:jmap:filenode');

  my $dir = JMAP::TestSuite::Entity::FileNode->scratch_dir($account);

  my $update = sub {
    my ($update, $extra) = @_;
    my $res = $tester->request([[ 'FileNode/set' => { update => $update, %{ $extra || {} } } ]]);
    ok($res->is_success, "FileNode/set") or diag explain $res->response_payload;
    return $res->single_sentence('FileNode/set')->arguments;
  };
  my $get = sub {
    my ($id) = @_;
    return $tester->request([[ 'FileNode/get' => { ids => [ $id ] } ]])
                  ->single_sentence('FileNode/get')->arguments->{list}[0];
  };

  my $a = $dir->add_node({ name => 'a' });
  my $b = $dir->add_node({ name => 'b' });
  my $file = $a->add_node({ name => 'f.txt', content => "content", type => 'text/plain' });

  subtest "rename" => sub {
    my $args = $update->({ $file->id => { name => 'g.txt' } });
    ok(exists $args->{updated}{ $file->id }, "updated") or diag explain $args;
    jcmp_deeply($get->($file->id), superhashof({ name => 'g.txt', parentId => $a->id }), "renamed in place");
  };

  subtest "move" => sub {
    my $args = $update->({ $file->id => { parentId => $b->id } });
    ok(exists $args->{updated}{ $file->id }, "updated") or diag explain $args;
    jcmp_deeply($get->($file->id), superhashof({ name => 'g.txt', parentId => $b->id }), "moved, same id");
  };

  subtest "move a directory and rename it in one update" => sub {
    my $args = $update->({ $a->id => { parentId => $b->id, name => 'a2' } });
    ok(exists $args->{updated}{ $a->id }, "updated") or diag explain $args;
    jcmp_deeply($get->($a->id), superhashof({ name => 'a2', parentId => $b->id }), "moved and renamed");
    # move it back for the cycle tests
    $args = $update->({ $a->id => { parentId => $dir->id, name => 'a' } });
    ok(exists $args->{updated}{ $a->id }, "moved back") or diag explain $args;
  };

  subtest "cycles" => sub {
    my $inner = $a->add_node({ name => 'inner' });
    my $deep  = $inner->add_node({ name => 'deep' });
    # draft S3.2.3: "an attempt to move a node to a parent for which this
    # node is also an ancestor is an error, and an invalidProperties error
    # will be returned"
    for my $case ([ 'its own child', $inner->id ], [ 'its grandchild', $deep->id ], [ 'itself', $a->id ]) {
      my ($what, $target) = @$case;
      my $args = $update->({ $a->id => { parentId => $target } });
      ok(!exists $args->{updated}{ $a->id }, "not moved into $what") or diag explain $args;
      jcmp_deeply($args->{notUpdated}{ $a->id }, invalid_properties('parentId'), "invalidProperties for $what")
        or diag explain $args;
    }
    is($get->($a->id)->{parentId}, $dir->id, "the directory has not moved");
  };

  subtest "nodeType is immutable" => sub {
    # draft S3.1 nodeType: "Attempting to change nodeType after creation is
    # an invalidProperties error"
    my $args = $update->({ $b->id => { nodeType => 'file' } });
    jcmp_deeply($args->{notUpdated}{ $b->id }, invalid_properties('nodeType'), "invalidProperties")
      or diag explain $args;
    is($get->($b->id)->{nodeType}, 'directory', "still a directory");
  };

  subtest "a name clash" => sub {
    my $c = $dir->add_node({ name => 'c' });
    # draft S3.2.3 onExists: "If null, an attempt to create or update a
    # FileNode which would cause a name collision will be rejected by the
    # server with an "alreadyExists" error"; the SetError "MUST include an
    # existingId property with the id of the existing FileNode"
    my $args = $update->({ $c->id => { name => 'b' } });
    jcmp_deeply($args->{notUpdated}{ $c->id }, superhashof({ type => 'alreadyExists', existingId => $b->id }),
                "rename onto a sibling: alreadyExists") or diag explain $args;
    my $x = $a->add_node({ name => 'b' });
    $args = $update->({ $x->id => { parentId => $dir->id } });
    jcmp_deeply($args->{notUpdated}{ $x->id }, superhashof({ type => 'alreadyExists', existingId => $b->id }),
                "move next to a same-named node: alreadyExists") or diag explain $args;
  };

  subtest "content" => sub {
    my $blob = $tester->upload({ accountId => $account->accountId, type => 'text/plain', blob => \"longer content" });
    # draft S3.1 size: "If the client updates blobId without providing
    # size, the server sets size from the new blob and returns the size in
    # the "updated" response"
    my $args = $update->({ $file->id => { blobId => $blob->blobId } });
    jcmp_deeply($args->{updated}{ $file->id }, superhashof({ size => jnum(14) }), "updated carries the new size")
      or diag explain $args;
    jcmp_deeply($get->($file->id), superhashof({ size => jnum(14), blobId => jstr() }), "the node has the new size");

    # draft S3.1 blobId: "Creating or updating a file node to have a null
    # blobId is an "invalidProperties" error"
    $args = $update->({ $file->id => { blobId => undef } });
    jcmp_deeply($args->{notUpdated}{ $file->id }, invalid_properties('blobId'), "a null blobId is invalidProperties")
      or diag explain $args;
  };

  subtest "modified is left alone" => sub {
    my $n = $dir->add_node({ name => 'dated.txt', content => "x", modified => '2020-01-02T03:04:05Z' });
    is($n->modified, '2020-01-02T03:04:05Z', "modified as created");
    # draft S3.1 modified: "If the client does not include modified in an
    # update, the server MUST leave it unchanged"
    my $args = $update->({ $n->id => { name => 'dated2.txt' } });
    ok(exists $args->{updated}{ $n->id }, "renamed") or diag explain $args;
    is($get->($n->id)->{modified}, '2020-01-02T03:04:05Z', "modified unchanged by a rename");
  };
};
