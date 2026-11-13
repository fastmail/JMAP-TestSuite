use jmaptest;

# RFC 8620 S5.3: "If a creation id is reused, the server MUST map the creation
# id to the most recently created item with that id."

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $res = $tester->request({
    createdIds  => {},
    methodCalls => [
      [ "Mailbox/set" => { create => { dup => { name => "reuse first $^T.$$" } } }, "t0" ],
      [ "Mailbox/set" => { create => { dup => { name => "reuse second $^T.$$" } } }, "t1" ],
      [ "Mailbox/set" => {
          create => { kid => { name => "reuse child $^T.$$", parentId => "#dup" } },
        }, "t2" ],
    ],
  });
  ok($res->is_success, "the request completed")
    or return diag explain $res->response_payload;

  my ($first, $second, $kid) = map {;
    eval { $res->sentence($_)->arguments->{created} }
  } 0 .. 2;
  my $first_id  = $first->{dup}{id};
  my $second_id = $second->{dup}{id};
  my $kid_id    = $kid->{kid}{id};

  ok($first_id && $second_id && $kid_id, "all three mailboxes were created")
    or return diag explain $res->as_stripped_triples;

  my $get = $tester->request([[
    "Mailbox/get" => { ids => [ $kid_id ], properties => [ "parentId" ] },
  ]]);
  is(
    $get->single_sentence("Mailbox/get")->arguments->{list}[0]{parentId},
    $second_id,
    '"#dup" referred to the second mailbox created as dup',
  ) or diag explain $get->as_stripped_triples;

  jcmp_deeply(
    $res->wrapper_properties->{createdIds},
    { dup => jstr($second_id), kid => jstr($kid_id) },
    "the createdIds returned map dup to the second mailbox",
  ) or diag explain $res->wrapper_properties;

  $tester->request([[ "Mailbox/set" => { destroy => [ $kid_id, $first_id, $second_id ] } ]]);
};
