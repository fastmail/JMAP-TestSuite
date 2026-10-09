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
  $mailbox->add_message;

  my $error_for = sub {
    my ($desc, $args) = @_;
    my $res = $tester->request([[
      "Email/query" => { filter => { inMailbox => $mailbox->id }, %$args },
    ]]);
    ok($res->is_success, "Email/query $desc")
      or diag explain $res->response_payload;
    return $res->sentence(0)->as_stripped_pair;
  };

  # RFC 8620 S5.5: "unsupportedSort": the sort "includes a property the
  # server does not support sorting on or a collation method it does not
  # recognise".
  for my $test (
    [ 'unknown sort property', [ { property => 'jmtsNoSuchProperty' } ] ],
    [ 'unknown collation',     [ { property => 'subject', collation => 'x-jmts-no-such-collation' } ] ],
  ) {
    my ($desc, $sort) = @$test;
    jcmp_deeply(
      $error_for->($desc, { sort => $sort }),
      [ error => superhashof({ type => 'unsupportedSort' }) ],
      "$desc is unsupportedSort",
    );
  }

  # RFC 8620 S5.5: "unsupportedFilter": the filter "is syntactically valid,
  # but the server cannot process it"; RFC 8621 S4.4.1 defines no such
  # condition, so invalidArguments is a fair answer too.
  jcmp_deeply(
    $error_for->('unknown filter condition', {
      filter => {
        operator   => 'AND',
        conditions => [
          { inMailbox => $mailbox->id },
          { jmtsNoSuchCondition => 'x' },
        ],
      },
    }),
    [ error => superhashof({ type => any(qw(unsupportedFilter invalidArguments)) }) ],
    "unknown filter condition is rejected",
  );
};
