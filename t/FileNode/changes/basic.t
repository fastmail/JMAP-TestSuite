use jmaptest;

# draft-ietf-jmap-filenode-15 (the draft) S3.2.2: "This is a standard
# Foo/changes method" (RFC 8620 S5.2).
attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities('urn:ietf:params:jmap:core', 'urn:ietf:params:jmap:filenode');

  my $D = JMAP::TestSuite::Entity::FileNode->scratch_dir($account);

  my $state = sub {
    $tester->request([[ 'FileNode/get' => { ids => [] } ]])->single_sentence('FileNode/get')->arguments->{state};
  };
  my $changes = sub {
    my ($since) = @_;
    my $res = $tester->request([[ 'FileNode/changes' => { sinceState => $since } ]]);
    ok($res->is_success, "FileNode/changes") or diag explain $res->response_payload;
    return $res->single_sentence('FileNode/changes')->arguments;
  };
  my $set = sub {
    my $res = $tester->request([[ 'FileNode/set' => $_[0] ]]);
    ok($res->is_success, "FileNode/set") or diag explain $res->response_payload;
    return $res->single_sentence('FileNode/set')->arguments;
  };

  my $s0 = $state->();
  ok(defined $s0, "FileNode/get gives a state");

  subtest "no changes" => sub {
    my $args = $changes->($s0);
    is($args->{oldState}, $s0, "oldState is sinceState");
    is($args->{newState}, $s0, "newState is unchanged");
    jcmp_deeply([ @{ $args->{created} }, @{ $args->{updated} }, @{ $args->{destroyed} } ], [], "nothing changed")
      or diag explain $args;
  };

  my $blob = $tester->upload({ accountId => $account->accountId, type => 'text/plain', blob => \"hello" });
  my $made = $set->({ create => {
    f => { '@type' => 'File', parentId => $D->id, name => 'f.txt', blobId => $blob->blobId, mediaType => 'text/plain' },
    d => { '@type' => 'Directory', parentId => $D->id, name => 'dir' },
  } });
  my ($fid, $did) = map {; $made->{created}{$_}{id} } qw(f d);
  ok($fid && $did, "created a file and a directory") or diag explain $made;
  # RFC 8620 S5.3: oldState / newState of a /set
  is($made->{oldState}, $s0, "FileNode/set oldState");
  my $s1 = $made->{newState};

  subtest "create" => sub {
    isnt($s1, $s0, "the state changed");
    my $args = $changes->($s0);
    is($args->{newState}, $s1, "newState is the set's newState");
    jcmp_deeply($args->{created}, bag($fid, $did), "both created") or diag explain $args;
    jcmp_deeply($args->{destroyed}, [], "nothing destroyed") or diag explain $args;
    # RFC 8620 S5.2: an id appears in at most one of the three lists
    ok(!grep({ $_ eq $fid || $_ eq $did } @{ $args->{updated} }), "not also updated") or diag explain $args;
  };

  my $s2 = $set->({ update => { $fid => { name => 'g.txt' } } })->{newState};

  subtest "update" => sub {
    my $args = $changes->($s1);
    is($args->{newState}, $s2, "newState");
    ok((grep { $_ eq $fid } @{ $args->{updated} }), "the renamed file is updated") or diag explain $args;
    ok(!grep({ $_ eq $did } @{ $args->{created} }, @{ $args->{updated} }, @{ $args->{destroyed} }),
       "the untouched directory is not listed") or diag explain $args;
  };

  my $s3 = $set->({ destroy => [ $fid ] })->{newState};

  subtest "destroy" => sub {
    my $args = $changes->($s2);
    jcmp_deeply($args->{destroyed}, [ $fid ], "the file is destroyed") or diag explain $args;
    is($args->{newState}, $s3, "newState");
  };

  subtest "since the start" => sub {
    # RFC 8620 S5.2: "If a record has been created AND destroyed since the
    # old state, the server SHOULD remove the id from the response entirely.
    # However, it MAY include it in just the "destroyed" list or in both the
    # "destroyed" and "created" lists."  The file was also updated, and an
    # updated and destroyed record "MAY" be in "updated" as well, so where
    # the file shows up is not checked; only the surviving directory is.
    my $args = $changes->($s0);
    jcmp_deeply([ grep { $_ ne $fid } @{ $args->{created} } ], [ $did ], "the directory is created")
      or diag explain $args;
    ok(!grep({ $_ eq $did } @{ $args->{destroyed} }), "the directory is not destroyed") or diag explain $args;
  };

  subtest "maxChanges" => sub {
    # two changes that survive: a fresh state, then two creations kept
    my $from = $state->();
    my $two = $set->({ create => {
      m1 => { '@type' => 'Directory', parentId => $D->id, name => 'm1' },
      m2 => { '@type' => 'Directory', parentId => $D->id, name => 'm2' },
    } });
    ok($two->{created}{m1} && $two->{created}{m2}, "two more nodes") or diag explain $two;
    # RFC 8620 S5.2: "the server MUST ensure the number of ids returned
    # across "created", "updated", and "destroyed" does not exceed this
    # limit"; cut short, the response is an intermediate state with
    # hasMoreChanges, or (if it cannot) cannotCalculateChanges
    my $res = $tester->request([[ 'FileNode/changes' => { sinceState => $from, maxChanges => 1 } ]]);
    my $s = $res->single_sentence;
    if ($s->name eq 'error') {
      is($s->arguments->{type}, 'cannotCalculateChanges', "an error is cannotCalculateChanges");
      return;
    }
    my $args = $s->arguments;
    my $n = @{ $args->{created} } + @{ $args->{updated} } + @{ $args->{destroyed} };
    cmp_ok($n, '<=', 1, "at most one change") or diag explain $args;
    ok($args->{hasMoreChanges}, "hasMoreChanges, with two changes to report") or diag explain $args;
  };

  subtest "bad state" => sub {
    # RFC 8620 S5.2: a state the server cannot work from is cannotCalculateChanges
    my $res = $tester->request([[ 'FileNode/changes' => { sinceState => 'no-such-state' } ]]);
    my $s = $res->single_sentence;
    is($s->name, 'error', "an error") or diag explain $res->response_payload;
    is($s->arguments->{type}, 'cannotCalculateChanges', "cannotCalculateChanges");
  };
};
