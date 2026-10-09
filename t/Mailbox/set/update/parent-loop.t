use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $top   = $account->create_mailbox;
  my $child = $top->add_mailbox;
  my $grand = $child->add_mailbox;

  # RFC 8621 S2: parentId forms "acyclic graphs (forests)" and "There MUST
  # NOT be a loop"; the update is invalid in the RFC 8620 S5.3 sense.
  for my $case (
    [ "parent is itself"         => $top->id   ],
    [ "parent is its child"      => $child->id ],
    [ "parent is its grandchild" => $grand->id ],
  ) {
    my ($desc, $parent_id) = @$case;

    subtest $desc => sub {
      my $res = $tester->request([[
        "Mailbox/set" => {
          update => { $top->id => { parentId => $parent_id } },
        },
      ]]);
      ok($res->is_success, "Mailbox/set") or diag explain $res->response_payload;

      my $args = $res->single_sentence("Mailbox/set")->arguments;
      ok(!exists $args->{updated}{ $top->id }, "update not applied")
        or diag explain $args;
      jcmp_deeply(
        $args->{notUpdated}{ $top->id },
        invalid_properties('parentId'),
        "notUpdated with invalidProperties",
      ) or diag explain $args;

      $tester->request_ok(
        [ "Mailbox/get" => { ids => [ $top->id ], properties => [ 'parentId' ] } ],
        superhashof({ list => [ superhashof({ parentId => undef }) ] }),
        "mailbox is still at the top level",
      );
    };
  }
};
