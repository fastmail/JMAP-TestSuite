use jmaptest;

# RFC 8620 S3.3 and S3.4: createdIds is returned only if given in the request,
# and then "MUST include all creation ids passed in" plus those created; a
# later request can pass it back to resolve "#" references.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $prior = $account->create_mailbox;

  subtest "not given, not returned" => sub {
    my $res = $tester->request([[ "Mailbox/get" => { ids => [] } ]]);
    ok($res->is_success, "the request completed")
      or return diag explain $res->response_payload;
    ok(!exists $res->wrapper_properties->{createdIds}, "no createdIds in the Response")
      or diag explain $res->wrapper_properties;
  };

  my %created;

  subtest "given, returned with the new ids added" => sub {
    my $res = $tester->request({
      createdIds  => { prior => $prior->id },
      methodCalls => [
        [ "Mailbox/set" => { create => { fresh => { name => "createdIds $^T.$$" } } } ],
      ],
    });
    ok($res->is_success, "the request completed")
      or return diag explain $res->response_payload;

    my $fresh = eval { $res->sentence(0)->arguments->{created}{fresh}{id} };
    ok($fresh, "the mailbox was created")
      or return diag explain $res->as_stripped_triples;

    jcmp_deeply(
      $res->wrapper_properties->{createdIds},
      { prior => jstr($prior->id), fresh => jstr($fresh) },
      "createdIds holds the id passed in and the one created",
    ) or diag explain $res->wrapper_properties;

    %created = %{ $res->wrapper_properties->{createdIds} // {} };
  };

  subtest "passed back, it resolves references" => sub {
    plan skip_all => "no createdIds from the previous request" unless $created{fresh};

    my $res = $tester->request({
      createdIds  => \%created,
      methodCalls => [
        [ "Mailbox/set" => {
            create => {
              kid1 => { name => "createdIds kid1 $^T.$$", parentId => "#fresh" },
              kid2 => { name => "createdIds kid2 $^T.$$", parentId => "#prior" },
            },
          } ],
      ],
    });
    ok($res->is_success, "the request completed")
      or return diag explain $res->response_payload;

    my $created = eval { $res->sentence(0)->arguments->{created} } // {};
    my @kids = grep {; defined } map {; $created->{$_}{id} } qw(kid1 kid2);
    is(@kids, 2, "both children were created")
      or return diag explain $res->as_stripped_triples;

    my $get = $tester->request([[
      "Mailbox/get" => { ids => \@kids, properties => [ "parentId" ] },
    ]]);
    my %parent = map {; $_->{id} => $_->{parentId} }
                 @{ $get->single_sentence("Mailbox/get")->arguments->{list} };
    is($parent{ $kids[0] }, $created{fresh}, '"#fresh" resolved via createdIds');
    is($parent{ $kids[1] }, $prior->id,      '"#prior" resolved via createdIds');

    jcmp_deeply(
      $res->wrapper_properties->{createdIds},
      { %created, kid1 => jstr($kids[0]), kid2 => jstr($kids[1]) },
      "createdIds again holds everything passed in and created",
    ) or diag explain $res->wrapper_properties;

    $tester->request([[ "Mailbox/set" => { destroy => \@kids } ]]);
  };
};
