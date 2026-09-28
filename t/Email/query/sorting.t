use jmaptest;

attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mailbox = $account->create_mailbox;

  my $flagged   = $mailbox->add_message({ subject => 'flagged',   keywords => { '$flagged' => jtrue() } });
  my $unflagged = $mailbox->add_message({ subject => 'unflagged', keywords => {} });

  subtest "sort by hasKeyword ascending puts unflagged first" => sub {
    my $res = $tester->request([[
      "Email/query" => {
        sort => [{ property => 'hasKeyword', keyword => '$flagged', isAscending => JSON::true }],
      },
    ]]);

    my $ids = $res->single_sentence('Email/query')->arguments->{ids};
    ok($ids && @$ids >= 2, 'got at least two results');

    my @pos = map { my $id = $_; my $i = 0; $i++ until $ids->[$i] eq $id; $i }
              ($unflagged->id, $flagged->id);
    ok($pos[0] < $pos[1], 'unflagged comes before flagged in ascending sort');
  };

  subtest "sort by hasKeyword descending puts flagged first" => sub {
    my $res = $tester->request([[
      "Email/query" => {
        sort => [{ property => 'hasKeyword', keyword => '$flagged', isAscending => JSON::false }],
      },
    ]]);

    my $ids = $res->single_sentence('Email/query')->arguments->{ids};
    ok($ids && @$ids >= 2, 'got at least two results');

    my @pos = map { my $id = $_; my $i = 0; $i++ until $ids->[$i] eq $id; $i }
              ($flagged->id, $unflagged->id);
    ok($pos[0] < $pos[1], 'flagged comes before unflagged in descending sort');
  };

  subtest "sort by receivedAt (basic sort field) works" => sub {
    my $res = $tester->request([[
      "Email/query" => {
        sort => [{ property => 'receivedAt', isAscending => JSON::true }],
      },
    ]]);

    my $ids = $res->single_sentence('Email/query')->arguments->{ids};
    ok($ids && @$ids >= 2, 'got results');
  };
};
