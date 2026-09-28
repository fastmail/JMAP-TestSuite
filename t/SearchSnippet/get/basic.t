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

  my $email = $mailbox->add_message({
    subject => 'Meeting about bananas',
    body    => 'We should discuss the banana supply chain in detail.',
  });

  my $other = $mailbox->add_message({
    subject => 'Unrelated topic',
    body    => 'Nothing fruity here at all.',
  });

  # Search indexing may be asynchronous (Cyrus's rolling squatter), so wait
  # until a query finds the message before asking for its snippets.
  my $indexed = 0;
  for my $attempt (1 .. 30) {
    my $ids = $tester->request([[
      "Email/query" => { filter => { subject => 'bananas' } },
    ]])->single_sentence("Email/query")->arguments->{ids} // [];
    if (grep { $_ eq $email->id } @$ids) { $indexed = 1; last }
    sleep 1;
  }
  ok($indexed, 'the message is searchable') or do {
    note('search index never caught up; skipping snippet assertions');
    return;
  };

  subtest "snippet with subject match" => sub {
    my $res = $tester->request([[
      "SearchSnippet/get" => {
        emailIds => [ $email->id ],
        filter   => { subject => 'bananas' },
      },
    ]]);
    ok($res->is_success, "SearchSnippet/get subject") or diag explain $res->response_payload;

    my $args = $res->single_sentence("SearchSnippet/get")->arguments;
    my @list = @{ $args->{list} };
    is(scalar @list, 1, "one snippet");

    my $snip = $list[0];
    is($snip->{emailId}, $email->id, "correct emailId");
    like($snip->{subject}, qr{<mark>}, "subject contains <mark> tag")
      or diag explain $snip;
  };

  subtest "snippet with body match" => sub {
    my $res = $tester->request([[
      "SearchSnippet/get" => {
        emailIds => [ $email->id ],
        filter   => { text => 'banana' },
      },
    ]]);
    ok($res->is_success, "SearchSnippet/get body") or diag explain $res->response_payload;

    my $args = $res->single_sentence("SearchSnippet/get")->arguments;
    my $snip = $args->{list}[0];
    ok(defined $snip->{preview} || defined $snip->{body}, "has preview or body snippet")
      or diag explain $snip;
    if (defined $snip->{preview}) {
      like($snip->{preview}, qr{<mark>}, "preview contains <mark> tag");
    }
  };

  subtest "no filter terms means no highlights" => sub {
    my $res = $tester->request([[
      "SearchSnippet/get" => {
        emailIds => [ $email->id ],
        filter   => {},
      },
    ]]);
    ok($res->is_success, "SearchSnippet/get no terms");

    my $snip = $res->single_sentence("SearchSnippet/get")->arguments->{list}[0];
    ok(!defined $snip->{subject}, "subject is undef with no filter terms");
    ok(!defined $snip->{preview}, "preview is undef with no filter terms");
  };

  subtest "multiple emailIds returned" => sub {
    my $res = $tester->request([[
      "SearchSnippet/get" => {
        emailIds => [ $email->id, $other->id ],
        filter   => { text => 'banana' },
      },
    ]]);
    ok($res->is_success, "SearchSnippet/get multiple ids");

    my $args = $res->single_sentence("SearchSnippet/get")->arguments;
    is(scalar @{ $args->{list} }, 2, "two snippets returned");

    my %by_id = map { $_->{emailId} => $_ } @{ $args->{list} };
    ok(exists $by_id{ $email->id },  "match email in results");
    ok(exists $by_id{ $other->id },  "non-match email in results");
  };
};
