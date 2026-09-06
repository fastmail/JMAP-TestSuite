use jmaptest;

# RFC 8620 S5.3: a record may reference another created in the same request via
# that record's creation id prefixed with "#". The client MUST order the calls
# so the referenced record is created first -- "the server never has to look
# ahead".

attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  subtest "create a mailbox and move messages into it in one request" => sub {
    my $source = $account->create_mailbox;
    my $email1 = $source->add_message;
    my $email2 = $source->add_message;

    my $name = "Moved $^T.$$";

    my $res = $tester->request({
      methodCalls => [
        [ "Mailbox/set" => {
            create => { newbox => { name => $name } },
          }, "t0" ],
        [ "Email/set" => {
            update => {
              $email1->id => { mailboxIds => { '#newbox' => \1 } },
              $email2->id => { mailboxIds => { '#newbox' => \1 } },
            },
          }, "t1" ],
      ],
    });
    ok($res->is_success, "the combined request succeeded")
      or diag explain $res->response_payload;

    my $mset = $res->sentence(0)->arguments;
    my $eset = $res->sentence(1)->arguments;

    my $new_id = $mset->{created}{newbox}{id};
    ok($new_id, 'the mailbox was created') or diag explain $mset;

    ok(exists $eset->{updated}{ $email1->id }, 'first email updated')
      or diag explain $eset;
    ok(exists $eset->{updated}{ $email2->id }, 'second email updated')
      or diag explain $eset;
    ok(!$eset->{notUpdated}, 'nothing in notUpdated')
      or diag explain $eset->{notUpdated};

    subtest "the messages really are in the new mailbox" => sub {
      my $get = $tester->request([[
        "Email/get" => {
          ids        => [ $email1->id, $email2->id ],
          properties => ['mailboxIds'],
        },
      ]]);
      ok($get->is_success, "Email/get");

      my $list = $get->single_sentence("Email/get")->arguments->{list} // [];
      is(scalar @$list, 2, 'both emails came back');

      for my $email (@$list) {
        jcmp_deeply(
          $email->{mailboxIds},
          { $new_id => jtrue() },
          "email $email->{id} is now only in the new mailbox",
        ) or diag explain $email->{mailboxIds};
      }
    };
  };

  subtest "a creation id may be referenced from a later call, not an earlier one" => sub {
    my $source = $account->create_mailbox;
    my $email  = $source->add_message;

    my $res = $tester->request({
      methodCalls => [
        [ "Email/set" => {
            update => {
              $email->id => { mailboxIds => { '#laterbox' => \1 } },
            },
          }, "t0" ],
        [ "Mailbox/set" => {
            create => { laterbox => { name => "Later $^T.$$" } },
          }, "t1" ],
      ],
    });
    ok($res->is_success, "the request itself did not fail")
      or diag explain $res->response_payload;

    my $eset = $res->sentence(0)->arguments;

    ok(!exists $eset->{updated}{ $email->id },
       'the forward reference did not apply the update')
      or diag explain $eset;
    ok($eset->{notUpdated}{ $email->id },
       'it is reported in notUpdated')
      or diag explain $eset;

    subtest "and the email did not move" => sub {
      my $get = $tester->request([[
        "Email/get" => {
          ids        => [ $email->id ],
          properties => ['mailboxIds'],
        },
      ]]);
      jcmp_deeply(
        $get->single_sentence("Email/get")->arguments->{list}[0]{mailboxIds},
        { $source->id => jtrue() },
        'still in its original mailbox only',
      );
    };
  };
};
