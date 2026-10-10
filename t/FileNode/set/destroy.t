use jmaptest;

# draft-ietf-jmap-filenode-15 (the draft) S3.2.3: destroying FileNodes,
# nodeHasChildren and onDestroyRemoveChildren.
attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities('urn:ietf:params:jmap:core', 'urn:ietf:params:jmap:filenode');

  my $dir = JMAP::TestSuite::Entity::FileNode->scratch_dir($account);

  my $set = sub {
    my ($args) = @_;
    my $res = $tester->request([[ 'FileNode/set' => $args ]]);
    ok($res->is_success, "FileNode/set") or diag explain $res->response_payload;
    return $res->single_sentence('FileNode/set')->arguments;
  };
  my $not_found = sub {
    my (@ids) = @_;
    my $args = $tester->request([[ 'FileNode/get' => { ids => \@ids, properties => [ 'name' ] } ]])
                      ->single_sentence('FileNode/get')->arguments;
    jcmp_deeply($args->{notFound}, bag(@ids), "FileNode/get: gone") or diag explain $args;
  };

  subtest "a file and an empty directory" => sub {
    my $f = $dir->add_node({ name => 'file.txt', content => "x" });
    my $d = $dir->add_node({ name => 'empty' });
    my $args = $set->({ destroy => [ $f->id, $d->id ] });
    jcmp_deeply($args->{destroyed}, bag($f->id, $d->id), "both destroyed") or diag explain $args;
    $not_found->($f->id, $d->id);
  };

  subtest "a directory with children" => sub {
    my $d = $dir->add_node({ name => 'full' });
    my $c = $d->add_node({ name => 'child.txt', content => "x" });
    # draft S3.2.3 onDestroyRemoveChildren: "If false, an attempt to destroy
    # a FileNode which is the parentId of another FileNode will be rejected
    # with a nodeHasChildren error"
    my $args = $set->({ destroy => [ $d->id ] });
    jcmp_deeply($args->{notDestroyed}{ $d->id }, superhashof({ type => 'nodeHasChildren' }), "nodeHasChildren")
      or diag explain $args;
    my $still = $tester->request([[ 'FileNode/get' => { ids => [ $d->id, $c->id ], properties => [ 'name' ] } ]])
                       ->single_sentence('FileNode/get')->arguments;
    is(scalar @{ $still->{list} }, 2, "the directory and its child are still there") or diag explain $still;
  };

  subtest "a directory and all its children in one call" => sub {
    my $d  = $dir->add_node({ name => 'together' });
    my $s  = $d->add_node({ name => 'sub' });
    my $c1 = $d->add_node({ name => 'c1.txt', content => "1" });
    my $c2 = $s->add_node({ name => 'c2.txt', content => "2" });
    # draft S3.2.3: "if all the child nodes are being destroyed in the same
    # operation, then the server MUST NOT return this error" -- the parent
    # is listed first, so a server cannot rely on the order
    my $args = $set->({ destroy => [ $d->id, $s->id, $c1->id, $c2->id ] });
    jcmp_deeply($args->{destroyed}, bag($d->id, $s->id, $c1->id, $c2->id), "all four destroyed")
      or diag explain $args;
    ok(!%{ $args->{notDestroyed} || {} }, "no notDestroyed") or diag explain $args;
    $not_found->($d->id, $s->id, $c1->id, $c2->id);
  };

  subtest "onDestroyRemoveChildren" => sub {
    my $d  = $dir->add_node({ name => 'tree' });
    my $s  = $d->add_node({ name => 'sub' });
    my $c1 = $d->add_node({ name => 'c1.txt', content => "1" });
    my $c2 = $s->add_node({ name => 'c2.txt', content => "2" });
    # draft S3.2.3 onDestroyRemoveChildren: "If true, then all child nodes
    # will also be destroyed ... the server MUST include the ids of all
    # deleted nodes in the method response"
    my $args = $set->({ onDestroyRemoveChildren => JSON::true, destroy => [ $d->id ] });
    jcmp_deeply($args->{destroyed}, bag($d->id, $s->id, $c1->id, $c2->id), "every destroyed id listed")
      or diag explain $args;
    $not_found->($d->id, $s->id, $c1->id, $c2->id);
  };

  subtest "an unknown id" => sub {
    # RFC 8620 S5.3: a destroy of an id that does not exist is notFound
    my $args = $set->({ destroy => [ 'nonexistent-filenode' ] });
    jcmp_deeply($args->{notDestroyed}{'nonexistent-filenode'}, superhashof({ type => 'notFound' }), "notFound")
      or diag explain $args;
  };

  subtest "a name freed and reused in one call" => sub {
    my $old = $dir->add_node({ name => 'reused.txt', content => "old" });
    my $blob = $tester->upload({ accountId => $account->accountId, type => 'text/plain', blob => \"new" });
    # draft S3.2.3: "A server MUST order creation and deletion operations
    # within a single FileNode/set such that the uniqueness of sibling names
    # is retained at the end of the transaction"
    my $args = $set->({
      destroy => [ $old->id ],
      create  => { n => { parentId => $dir->id, name => 'reused.txt', blobId => $blob->blobId, type => 'text/plain' } },
    });
    jcmp_deeply($args->{destroyed}, [ $old->id ], "the old node destroyed") or diag explain $args;
    ok($args->{created}{n}, "and a new one created with its name") or diag explain $args;
  };
};
