use jmaptest;

# Can't have existing messages so must be pristine
attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester = $account->tester;

  my $mailbox = $account->create_mailbox({ name => "aaa" });

  my $match = $mailbox->add_message({ subject => 'aaa' });
  my $no_match = $mailbox->add_message({ subject => 'bbb' });

  my %emails = (
    match => $match,
    no_match => $no_match,
  );
  my %emails_by_id = map {; $_->id => $_ } values %emails;
  my $describer_sub = $self->make_describer_sub(\%emails_by_id);

  my %args = (
    filter => {
      text => "aaa",
    },
    sort   => [{ property => 'subject', isAscending => jtrue()  }],
  );

  # Ugh, squatter needs time to index things
  sleep 1 if $self->server->isa('JMAP::TestSuite::ServerAdapter::Cyrus');

  # Get our baseline
  my ($baseline_res) = $self->test_query(
    $account,
    "Email/query",
    \%args,
    {
      ids => [ $match->id, ],
    },
    $describer_sub,
    "text search",
  );

  my $query_state = $baseline_res->sentence(0)->arguments->{queryState};
  ok($query_state, 'got a query state');

  subtest "no changes" => sub {
    $tester->request_ok(
      [
        "Email/queryChanges" => {
          %args,
          sinceQueryState => $query_state,
        },
      ],
      superhashof({
        %args,
        oldQueryState => $query_state,
        newQueryState => $query_state,
        added         => [ ],
        removed       => [ ],
      }),
      "expected resposne",
    );
  };

  my $match2 = $mailbox->add_message({ subject => 'aaa 2' });

  # Ugh, squatter needs time to index things
  sleep 1 if $self->server->isa('JMAP::TestSuite::ServerAdapter::Cyrus');

  subtest "added message that matches" => sub {
    my ($res) = $tester->request_ok(
      [
        "Email/queryChanges" => {
          %args,
          sinceQueryState => $query_state,
        },
      ],
      superhashof({
        %args,
        oldQueryState => $query_state,
        newQueryState => none($query_state),
        added         => [ { id => $match2->id, index => 1 }, ],
        removed       => ignore, # XXX - Too volatile -- alh, 2018-09-11
      }),
      "expected resposne",
    );

    $query_state = $res->sentence(0)->arguments->{newQueryState};
    ok($query_state, 'still have a query state');
  };

  my $no_match2 = $mailbox->add_message({ subject => 'bbb 2' });

  # Ugh, squatter needs time to index things
  sleep 1 if $self->server->isa('JMAP::TestSuite::ServerAdapter::Cyrus');

  subtest "added message that doesn't match" => sub {
    my ($res) = $tester->request_ok(
      [
        "Email/queryChanges" => {
          %args,
          sinceQueryState => $query_state,
        },
      ],
      superhashof({
        %args,
        oldQueryState => $query_state,
        newQueryState => none($query_state),
        added         => [ ],
        removed       => [ ],
      }),
      "expected resposne",
    );

    $query_state = $res->sentence(0)->arguments->{newQueryState};
    ok($query_state, 'still have a query state');
  };

  # Destroy a matching message
  $tester->request_ok(
    [
      "Email/set" => {
        destroy => [ $match->id ],
      },
    ],
    superhashof({
      destroyed => [ $match->id ],
    }),
    'destroyed a message'
  );

  subtest "a removal that matches" => sub {
    my ($res) = $tester->request_ok(
      [
        "Email/queryChanges" => {
          %args,
          sinceQueryState => $query_state,
        },
      ],
      superhashof({
        %args,
        oldQueryState => $query_state,
        newQueryState => none($query_state),
        added         => [ ],
        removed       => supersetof($match->id),
      }),
      "expected resposne",
    );

    $query_state = $res->sentence(0)->arguments->{newQueryState};
    ok($query_state, 'still have a query state');
  };

  # Destroy a non-matching message
  $tester->request_ok(
    [
      "Email/set" => {
        destroy => [ $no_match2->id ],
      },
    ],
    superhashof({
      destroyed => [ $no_match2->id ],
    }),
    'destroyed a message'
  );

  subtest "a removal that doesn't match" => sub {
    my ($res) = $tester->request_ok(
      [
        "Email/queryChanges" => {
          %args,
          sinceQueryState => $query_state,
        },
      ],
      superhashof({
        %args,
        oldQueryState => $query_state,
        newQueryState => none($query_state),
        added         => [ ],
        removed       => [ ],
      }),
      "expected resposne",
    );

    $query_state = $res->sentence(0)->arguments->{newQueryState};
    ok($query_state, 'still have a query state');
  };
};

sub make_describer_sub {
  my ($self, $emails_by_id) = @_;

  return sub {
    my ($self, $id) = @_;

    return    $emails_by_id->{$id}->{subject}
           || $emails_by_id->{$id}->subject;
  }
}
