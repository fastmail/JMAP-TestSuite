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

  my @email = map {;
    $mailbox->add_message({
      subject    => "window $_ $$",
      receivedAt => "2020-01-01T00:00:0${_}Z",
    })
  } 0 .. 4;

  my %base = (
    filter => { inMailbox => $mailbox->id },
    sort   => [ { property => 'receivedAt', isAscending => jtrue() } ],
  );

  my $query = sub {
    my ($desc, $args) = @_;
    my $res = $tester->request([[ "Email/query" => { %base, %$args } ]]);
    ok($res->is_success, "Email/query $desc")
      or diag explain $res->response_payload;
    return $res->is_success ? $res->single_sentence : undef;
  };

  # RFC 8620 S5.5: a negative position "MUST be added to the total number of
  # results given the filter, and if still negative, it's clamped to "0"".
  for my $test (
    [ 'position 1, limit 2', { position =>   1, limit => 2 }, 1, [ 1, 2 ] ],
    [ 'position -2',         { position =>  -2 },             3, [ 3, 4 ] ],
    [ 'position -2, limit 1',{ position =>  -2, limit => 1 }, 3, [ 3 ] ],
    [ 'position -10',        { position => -10 },             0, [ 0 .. 4 ] ],
    [ 'limit 0',             { limit    =>   0 },             0, [] ],
  ) {
    my ($desc, $args, $position, $want) = @$test;

    my $sentence = $query->($desc, { %$args, calculateTotal => jtrue() })
      or next;
    my %got = %{ $sentence->arguments };

    # RFC 8620 S5.5: limit is returned only "if set by the server".
    delete $got{limit};

    jcmp_deeply(
      \%got,
      {
        accountId           => jstr($account->accountId),
        queryState          => jstr(),
        canCalculateChanges => jbool(),
        position            => jnum($position),
        ids                 => [ map {; jstr($email[$_]->id) } @$want ],
        total               => jnum(5),
      },
      "$desc gives position $position and ids [@$want]",
    ) or diag explain $sentence->as_stripped_pair;
  }

  subtest "position past the end" => sub {
    my $sentence = $query->('position 5', { position => 5 }) or return;
    # RFC 8620 S5.5: "If "position" is >= "total", this MUST be the empty
    # list."
    jcmp_deeply($sentence->arguments->{ids}, [], "no ids")
      or diag explain $sentence->as_stripped_pair;
  };

  subtest "total only when asked for" => sub {
    my $sentence = $query->('without calculateTotal', {}) or return;
    # RFC 8620 S5.5: total "MUST be omitted if the "calculateTotal" request
    # argument is not true".
    ok(! exists $sentence->arguments->{total}, "no total")
      or diag explain $sentence->as_stripped_pair;
  };

  subtest "negative limit" => sub {
    my $sentence = $query->('limit -1', { limit => -1 }) or return;
    # RFC 8620 S5.5: "If a negative value is given, the call MUST be rejected
    # with an "invalidArguments" error."
    jcmp_deeply(
      $sentence->as_stripped_pair,
      [ error => superhashof({ type => 'invalidArguments' }) ],
      "rejected",
    );
  };
};
