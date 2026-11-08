use jmaptest;

# draft-ietf-jmap-filenode-15 (the draft) S3.2.3: the onExists and
# compareCaseInsensitively arguments of FileNode/set.
attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities('urn:ietf:params:jmap:core', 'urn:ietf:params:jmap:filenode');

  my $cap = JMAP::TestSuite::Entity::FileNode->capability($account) or return;
  my $dir = JMAP::TestSuite::Entity::FileNode->scratch_dir($account);

  my $blob = $tester->upload({ accountId => $account->accountId, type => 'text/plain', blob => \"incoming" });
  my $set = sub {
    my ($args) = @_;
    my $res = $tester->request([[ 'FileNode/set' => $args ]]);
    ok($res->is_success, "FileNode/set") or diag explain $res->response_payload;
    return $res->single_sentence('FileNode/set')->arguments;
  };
  my $file = sub {
    my ($name, %extra) = @_;
    return { '@type' => 'File', parentId => $dir->id, name => $name, blobId => $blob->blobId, mediaType => 'text/plain', %extra };
  };
  my $children = sub {
    my $args = $tester->request([[ 'FileNode/query' => { filter => { parentId => $dir->id } }, 'q' ],
                                 [ 'FileNode/get' => { '#ids' => { resultOf => 'q', name => 'FileNode/query', path => '/ids' },
                                                       properties => [ 'name' ] }, 'g' ]])
                      ->sentence(1)->arguments;
    return { map {; $_->{name} => $_->{id} } @{ $args->{list} } };
  };

  subtest "replace" => sub {
    my $old = $dir->add_node({ name => 'replace.txt', content => "old" });
    # draft S3.2.3 onExists "replace": "the existing item will be destroyed
    # ... the server MUST include the id of the replaced item in the
    # destroyed response list"
    my $args = $set->({ onExists => 'replace', create => { r => $file->('replace.txt') } });
    ok($args->{created}{r}, "created") or diag explain $args;
    jcmp_deeply($args->{destroyed}, [ $old->id ], "the replaced node is in destroyed") or diag explain $args;
    is($children->()->{'replace.txt'}, $args->{created}{r}{id}, "the name is the new node's");
  };

  subtest "replace a directory with children" => sub {
    my $old = $dir->add_node({ name => 'full' });
    my $kid = $old->add_node({ name => 'kid.txt', content => "x" });
    # draft S3.2.3 onExists "replace": "if the replaced item is a directory
    # which has children, then the server MUST respond with a
    # nodeHasChildren error to this action unless onDestroyRemoveChildren is
    # true"
    my $args = $set->({ onExists => 'replace', create => { r => $file->('full') } });
    jcmp_deeply($args->{notCreated}{r}, superhashof({ type => 'nodeHasChildren' }), "nodeHasChildren")
      or diag explain $args;
    is($children->()->{full}, $old->id, "the directory is still there");

    $args = $set->({ onExists => 'replace', onDestroyRemoveChildren => JSON::true, create => { r => $file->('full') } });
    ok($args->{created}{r}, "with onDestroyRemoveChildren, created") or diag explain $args;
    jcmp_deeply($args->{destroyed}, bag($old->id, $kid->id), "the directory and its child are destroyed")
      or diag explain $args;
  };

  subtest "replace by a rename" => sub {
    my $target = $dir->add_node({ name => 'target.txt', content => "t" });
    my $mover  = $dir->add_node({ name => 'mover.txt', content => "m" });
    # draft S3.2.3 onExists: it applies to an attempt "to create or update"
    my $args = $set->({ onExists => 'replace', update => { $mover->id => { name => 'target.txt' } } });
    ok(exists $args->{updated}{ $mover->id }, "updated") or diag explain $args;
    jcmp_deeply($args->{destroyed}, [ $target->id ], "the node it replaced is in destroyed") or diag explain $args;
    is($children->()->{'target.txt'}, $mover->id, "the name is the moved node's");
  };

  subtest "rename" => sub {
    my $old = $dir->add_node({ name => 'rename.txt', content => "old" });
    # draft S3.2.3 onExists "rename": "the server will change the "name"
    # field to not clash ... it MUST include the new "name" value in the
    # created or updated response field for this id"
    my $args = $set->({ onExists => 'rename', create => { r => $file->('rename.txt') } });
    jcmp_deeply($args->{created}{r}, superhashof({ id => jstr(), name => jstr() }), "created, with its name")
      or diag explain $args;
    my $name = $args->{created}{r}{name} // '';
    isnt($name, 'rename.txt', "a different name");
    my $kids = $children->();
    is($kids->{'rename.txt'}, $old->id, "the existing node keeps its name");
    is($kids->{$name}, $args->{created}{r}{id}, "the new node has the name it was given");
    ok(!$args->{destroyed} || !@{ $args->{destroyed} }, "nothing destroyed") or diag explain $args;
  };

  subtest "no other values" => sub {
    # draft-ietf-jmap-filenode-20 S3.2.3 onExists: null, "replace" or
    # "rename" ("newest" went in -19); "Any other value is rejected with
    # invalidArguments"
    for my $v ('newest', 'unchanged', 'bogus') {
      my $res = $tester->request([[ 'FileNode/set' => { onExists => $v, create => { r => $file->("odd-$v.txt") } } ]]);
      jcmp_deeply($res->single_sentence->arguments, superhashof({ type => 'invalidArguments' }),
                  "onExists \"$v\": invalidArguments") or diag explain $res->response_payload;
    }
  };

  subtest "compareCaseInsensitively" => sub {
    plan skip_all => "the server's names are case-insensitive already" if $cap->{caseInsensitiveNames};
    my $old = $dir->add_node({ name => 'Mixed.txt', content => "old" });
    # draft S3.2.3 compareCaseInsensitively: "If true, name collision
    # checks (including onExists handling) treat names as case-insensitive
    # for this request"
    my $args = $set->({ compareCaseInsensitively => JSON::true, create => { r => $file->('mixed.TXT') } });
    jcmp_deeply($args->{notCreated}{r}, superhashof({ type => 'alreadyExists', existingId => $old->id }),
                "a case-only difference is a clash") or diag explain $args;
    $args = $set->({ create => { r => $file->('mixed.TXT') } });
    ok($args->{created}{r}, "without it (default false), the names differ") or diag explain $args;
  };
};
