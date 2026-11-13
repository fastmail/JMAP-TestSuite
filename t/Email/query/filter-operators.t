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

  my %email;
  my $n = 0;
  for my $test (
    [ k1   => [ 'jmts_k1' ] ],
    [ k2   => [ 'jmts_k2' ] ],
    [ both => [ 'jmts_k1', 'jmts_k2' ] ],
    [ none => [] ],
  ) {
    my ($name, $keywords) = @$test;
    $n++;
    $email{$name} = $mailbox->add_message({
      subject    => "operator $name",
      receivedAt => "2020-01-01T00:00:0${n}Z",
      keywords   => { map {; $_ => jtrue() } @$keywords },
    });
  }

  my $in_mailbox = { inMailbox => $mailbox->id };
  my $k1 = { hasKeyword => 'jmts_k1' };
  my $k2 = { hasKeyword => 'jmts_k2' };

  # RFC 8620 S5.5: AND, OR and NOT mean all, at least one, and none of the
  # conditions must match.
  for my $test (
    [ 'AND of conditions',   [ $k1, $k2 ],                         [ qw(both) ] ],
    [ 'OR of conditions',    [ { operator => 'OR',  conditions => [ $k1, $k2 ] } ], [ qw(k1 k2 both) ] ],
    [ 'NOT of conditions',   [ { operator => 'NOT', conditions => [ $k1, $k2 ] } ], [ qw(none) ] ],
    [ 'NOT of an AND',       [ { operator => 'NOT', conditions => [
                                 { operator => 'AND', conditions => [ $k1, $k2 ] },
                               ] } ],                              [ qw(k1 k2 none) ] ],
  ) {
    my ($desc, $conditions, $want) = @$test;

    my $res = $tester->request([[
      "Email/query" => {
        filter => {
          operator   => 'AND',
          conditions => [ $in_mailbox, @$conditions ],
        },
        sort   => [ { property => 'receivedAt', isAscending => jtrue() } ],
      },
    ]]);
    ok($res->is_success, "Email/query $desc")
      or diag explain $res->response_payload;

    jcmp_deeply(
      $res->single_sentence("Email/query")->arguments->{ids},
      [ map {; jstr($email{$_}->id) } @$want ],
      "$desc gives @$want",
    ) or diag explain $res->as_stripped_triples;
  }
};
