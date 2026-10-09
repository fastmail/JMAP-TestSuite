use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mailbox = $account->create_mailbox;

  # RFC 8621 S2: sortOrder "MUST be an integer in the range
  # 0 <= sortOrder < 2^31".
  for my $bad (-1, 2_147_483_648) {
    subtest "create with sortOrder $bad" => sub {
      my $res = $tester->request([[
        "Mailbox/set" => {
          create => {
            bad => { name => "Sort $bad $^T.$$", sortOrder => $bad },
          },
        },
      ]]);
      ok($res->is_success, "Mailbox/set") or diag explain $res->response_payload;

      my $args = $res->single_sentence("Mailbox/set")->arguments;
      ok(!$args->{created}{bad}, "Mailbox not created") or diag explain $args;
      jcmp_deeply(
        $args->{notCreated}{bad},
        invalid_properties('sortOrder'),
        "notCreated with invalidProperties",
      ) or diag explain $args;
    };

    subtest "update to sortOrder $bad" => sub {
      my $res = $tester->request([[
        "Mailbox/set" => {
          update => { $mailbox->id => { sortOrder => $bad } },
        },
      ]]);
      ok($res->is_success, "Mailbox/set") or diag explain $res->response_payload;

      my $args = $res->single_sentence("Mailbox/set")->arguments;
      ok(!exists $args->{updated}{ $mailbox->id }, "update not applied")
        or diag explain $args;
      jcmp_deeply(
        $args->{notUpdated}{ $mailbox->id },
        invalid_properties('sortOrder'),
        "notUpdated with invalidProperties",
      ) or diag explain $args;
    };
  }
};
