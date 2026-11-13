use jmaptest;

# RFC 8620 S3.7: a "*" token in a ResultReference path maps the rest of the
# pointer over every item of an array, and arrays so produced are flattened.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mailbox = $account->create_mailbox;
  my $first   = $mailbox->add_message({ subject => "wildcard one $^T.$$" });
  my $reply   = $first->reply({ subject => "Re: wildcard one $^T.$$" });
  my $other   = $mailbox->add_message({ subject => "wildcard two $^T.$$" });

  my $res = $tester->request([
    [ "Email/query" => { filter => { inMailbox => $mailbox->id } }, "t0" ],
    [ "Email/get" => {
        "#ids" => { resultOf => "t0", name => "Email/query", path => "/ids" },
        properties => [ "threadId" ],
      }, "t1" ],
    [ "Thread/get" => {
        "#ids" => { resultOf => "t1", name => "Email/get", path => "/list/*/threadId" },
      }, "t2" ],
    [ "Email/get" => {
        "#ids" => { resultOf => "t2", name => "Thread/get", path => "/list/*/emailIds" },
        properties => [ "threadId" ],
      }, "t3" ],
  ]);
  ok($res->is_success, "the chained request succeeded")
    or return diag explain $res->response_payload;

  my @names = map {; $_->name } $res->sentences;
  is_deeply(
    \@names,
    [ "Email/query", "Email/get", "Thread/get", "Email/get" ],
    "every call resolved its reference",
  ) or return diag explain $res->as_stripped_triples;

  my $emails  = $res->sentence(1)->arguments->{list};
  my %threads = map {; $_->{id} => $_->{threadId} } @$emails;

  is(keys %threads, 3, "Email/get found all three emails")
    or diag explain $emails;

  my $thread_list = $res->sentence(2)->arguments->{list};
  jcmp_deeply(
    [ map {; $_->{id} } @$thread_list ],
    bag(keys %{{ map {; $_ => 1 } values %threads }}),
    "Thread/get got each threadId once, from /list/*/threadId",
  ) or diag explain $res->as_stripped_triples;

  my @all_email_ids = map {; @{ $_->{emailIds} } } @$thread_list;
  jcmp_deeply(
    [ map {; $_->{id} } @{ $res->sentence(3)->arguments->{list} } ],
    bag(@all_email_ids),
    "/list/*/emailIds flattened into a single list of ids",
  ) or diag explain $res->as_stripped_triples;

  jcmp_deeply(
    $res->sentence(3)->arguments->{notFound},
    [],
    "every flattened id was a real email",
  ) or diag explain $res->as_stripped_triples;
};
