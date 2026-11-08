use jmaptest;

# draft-ietf-jmap-filenode-15 (the draft) S3.1 and S3.2.3: FileNode/set
# update -- rename, move, cycles, immutable @type, content.
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
  my $file = $a->add_node({ name => 'f.txt', content => "content", mediaType => 'text/plain' });

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
    # will be returned".  A node as its own parent is the degenerate case,
    # and in any event an invalid parentId: RFC 8620 S5.3 invalidProperties,
    # "The record given is invalid in some way"
    for my $case ([ 'its own child', $inner->id ], [ 'its grandchild', $deep->id ], [ 'itself', $a->id ]) {
      my ($what, $target) = @$case;
      my $args = $update->({ $a->id => { parentId => $target } });
      ok(!exists $args->{updated}{ $a->id }, "not moved into $what") or diag explain $args;
      jcmp_deeply($args->{notUpdated}{ $a->id }, invalid_properties('parentId'), "invalidProperties for $what")
        or diag explain $args;
    }
    is($get->($a->id)->{parentId}, $dir->id, "the directory has not moved");
  };

  subtest "\@type is immutable" => sub {
    # draft S3.1.1 @type: "(immutable)" -- an update changing it is
    # invalidProperties (RFC 8620 S5.3)
    my $args = $update->({ $b->id => { '@type' => 'File' } });
    jcmp_deeply($args->{notUpdated}{ $b->id }, invalid_properties('@type'), "invalidProperties")
      or diag explain $args;
    is($get->($b->id)->{'@type'}, 'Directory', "still a Directory");
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

    # and when the client never set them: draft S3.1 modified, "The server
    # does not automatically update this value"; created, "The date the
    # node was created" -- a rename or move is neither.  The wait lets a
    # server that keeps its own timestamps per path show a change.
    # (plain structures throughout: the values are compared with each other)
    my $plain = sub {
      my ($id) = @_;
      $tester->request([[ 'FileNode/get' => { ids => [ $id ] } ]])->single_sentence('FileNode/get')->as_stripped_pair->[1]{list}[0];
    };
    my $m = $dir->add_node({ name => 'undated.txt', content => "x" });
    my $before = $plain->($m->id);
    sleep 2;
    my $res = $tester->request([[ 'FileNode/set' => { update => { $m->id => { name => 'undated2.txt', parentId => $b->id } } } ]]);
    ok($res->is_success, "FileNode/set") or diag explain $res->response_payload;
    my $sargs = $res->single_sentence('FileNode/set')->as_stripped_pair->[1];
    ok(exists $sargs->{updated}{ $m->id }, "moved and renamed") or diag explain $sargs;
    my $after = $plain->($m->id);
    is($after->{modified}, $before->{modified}, "modified unchanged by a move the client did not date");
    is($after->{created}, $before->{created}, "created unchanged too");

    # RFC 8620 S5.3 updated: "containing any property that changed in a way
    # not explicitly requested by the PatchObject": whatever the updated
    # object carries is the node's value now
    my $u = $sargs->{updated}{ $m->id } || {};
    for my $k (sort keys %$u) {
      is_deeply($u->{$k}, $after->{$k}, "updated.$k is the node's value now");
    }
  };
};
