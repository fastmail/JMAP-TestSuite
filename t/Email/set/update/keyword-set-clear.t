use jmaptest;
use JMAP::TestSuite::Util qw(client_keywords);

# Every way to set a keyword and every way to clear one, in each combination,
# and the values that must be refused.  RFC 8621 S4.1.1: keywords is
# String[Boolean] and "The value MUST always be true"; RFC 8620 S5.3: a patch
# key sets its value, and null removes it.  (From rjbs's PR #21, 2018.)

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mbox = $account->create_mailbox;

  my @setters = (
    [ 'whole keywords object' => { keywords => { '$flagged' => jtrue } } ],
    [ 'patch to true'         => { 'keywords/$flagged' => jtrue } ],
  );
  my @clearers = (
    [ 'whole keywords object, empty' => { keywords => {} } ],
    [ 'patch to null'                => { 'keywords/$flagged' => undef } ],
  );

  my $keywords_are = sub {
    my ($id, $want, $desc) = @_;
    $tester->request_ok(
      [ "Email/get" => { ids => [ $id ], properties => [ 'keywords' ] } ],
      superhashof({ list => [ superhashof({ keywords => client_keywords($want) }) ] }),
      $desc,
    );
  };

  my $update = sub {
    my ($id, $patch) = @_;
    my $res = $tester->request([[ "Email/set" => { update => { $id => $patch } } ]]);
    return $res->single_sentence('Email/set')->arguments;
  };

  for my $setter (@setters) {
    for my $clearer (@clearers) {
      subtest "set by $setter->[0], clear by $clearer->[0]" => sub {
        my $message = $mbox->add_message({ subject => "keywords $$" });
        my $id = $message->id;

        $keywords_are->($id, {}, "a new email has no keywords");

        my $set = $update->($id, $setter->[1]);
        ok(exists $set->{updated}{$id}, "set: updated") or diag explain $set;
        $keywords_are->($id, { '$flagged' => jtrue }, "set: \$flagged is there");

        my $clear = $update->($id, $clearer->[1]);
        ok(exists $clear->{updated}{$id}, "clear: updated") or diag explain $clear;
        $keywords_are->($id, {}, "clear: \$flagged is gone");
      };
    }
  }

  # A keyword's value "MUST always be true": anything else is not a keyword
  # value, so the update is invalidProperties and the email is unchanged.
  for my $bad (
    [ 'a patch to 1'                => { 'keywords/$flagged' => 1 } ],
    [ 'a patch to false'            => { 'keywords/$flagged' => jfalse } ],
    [ 'a keywords object with false' => { keywords => { '$flagged' => jfalse } } ],
  ) {
    subtest "refused: $bad->[0]" => sub {
      my $message = $mbox->add_message({ subject => "keywords $$" });
      my $id = $message->id;

      my $res = $update->($id, $bad->[1]);
      jcmp_deeply(
        $res->{notUpdated}{$id},
        superhashof({ type => 'invalidProperties' }),
        "notUpdated, invalidProperties",
      ) or diag explain $res;
      ok(!exists $res->{updated}{$id}, "not updated");

      $keywords_are->($id, {}, "the email still has no keywords");
    };
  }
};
