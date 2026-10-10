use jmaptest;

# draft-ietf-jmap-filenode-15 (the draft) presumes zero-byte files exist: S3.1
# blobId "MUST be non-null for file nodes (including zero byte files)", and
# size is "The size in bytes of the associated blob data".  So a file node
# with empty content can be created, and its size is 0.
attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities('urn:ietf:params:jmap:core', 'urn:ietf:params:jmap:filenode');

  my $dir   = JMAP::TestSuite::Entity::FileNode->scratch_dir($account);
  my $empty = $tester->upload({ accountId => $account->accountId, type => 'text/plain', blob => \"" });

  my $res = $tester->request([[ 'FileNode/set' => {
    create => { z => { parentId => $dir->id, name => 'empty.txt', blobId => $empty->blobId, type => 'text/plain' } },
  } ]]);
  ok($res->is_success, "FileNode/set") or diag explain $res->response_payload;
  my $args = $res->single_sentence('FileNode/set')->arguments;
  # size is server-set, so (RFC 8620 S5.3) it is in created
  jcmp_deeply($args->{created}{z}, superhashof({ id => jstr(), size => jnum(0) }), "a zero-byte file, size 0")
    or diag explain $args;
  my $id = $args->{created}{z}{id} or return;

  my $got = $tester->request([[ 'FileNode/get' => { ids => [ $id ] } ]])
                   ->single_sentence('FileNode/get')->arguments->{list}[0];
  jcmp_deeply($got, superhashof({ nodeType => 'file', blobId => jstr(), size => jnum(0) }),
              "FileNode/get: a file with a blobId and size 0") or diag explain $got;
};
