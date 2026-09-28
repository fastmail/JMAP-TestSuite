use jmaptest;

# Changing a mailbox's contents must move the containing Mailbox's own state,
# and a destroyed mailbox must appear as a tombstone in Mailbox/queryChanges.
#
# RFC 8621 S2.2: updatedProperties is "String[]|null", and a server unable to
# tell whether only counts changed MUST send null -- so null is acceptable.

attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my %COUNT_PROPERTY = map {; $_ => 1 }
    qw(totalEmails unreadEmails totalThreads unreadThreads);

  subtest "adding a message updates the containing mailbox" => sub {
    my $mailbox = $account->create_mailbox;

    my $state = $tester->request([[
      "Mailbox/get" => { ids => [] },
    ]])->single_sentence("Mailbox/get")->arguments->{state};

    my $email = $mailbox->add_message;

    my $res = $tester->request([[
      "Mailbox/changes" => { sinceState => $state },
    ]]);
    ok($res->is_success, "Mailbox/changes") or diag explain $res->response_payload;

    my $sent = $res->single_sentence;
    if ($sent->name eq 'error') {
      is($sent->arguments->{type}, 'cannotCalculateChanges',
         'only cannotCalculateChanges is acceptable here');
      note('cannot verify container state tracking without a usable state');
      return;
    }

    my $args = $sent->arguments;

    ok(grep { $_ eq $mailbox->id } @{ $args->{updated} // [] },
       'the mailbox is reported as updated after gaining a message')
      or diag explain $args;

    isnt($args->{newState}, $state, 'the Mailbox state moved');

    if (defined $args->{updatedProperties}) {
      my @unexpected = grep { !$COUNT_PROPERTY{$_} }
                       @{ $args->{updatedProperties} };
      ok(!@unexpected,
         'updatedProperties lists only count properties')
        or diag "unexpected: @unexpected";
    }
    else {
      note('updatedProperties is null: server does not distinguish '
         . 'count-only changes, which RFC 8621 S2.2 explicitly permits');
    }

    subtest "and the count actually reflects the message" => sub {
      my $get = $tester->request([[
        "Mailbox/get" => {
          ids        => [ $mailbox->id ],
          properties => [ 'totalEmails' ],
        },
      ]]);
      is($get->single_sentence("Mailbox/get")->arguments->{list}[0]{totalEmails},
         1, 'totalEmails is 1');
    };

    subtest "removing the message updates it again" => sub {
      my $state2 = $tester->request([[
        "Mailbox/get" => { ids => [] },
      ]])->single_sentence("Mailbox/get")->arguments->{state};

      my $del = $tester->request([[
        "Email/set" => { destroy => [ $email->id ] },
      ]]);
      ok(grep { $_ eq $email->id }
           @{ $del->single_sentence("Email/set")->arguments->{destroyed} // [] },
         'email destroyed');

      my $res2 = $tester->request([[
        "Mailbox/changes" => { sinceState => $state2 },
      ]]);
      my $sent2 = $res2->single_sentence;
      return if $sent2->name eq 'error';

      ok(grep { $_ eq $mailbox->id } @{ $sent2->arguments->{updated} // [] },
         'the mailbox is reported as updated after losing the message')
        or diag explain $sent2->arguments;
    };
  };

  subtest "queryChanges reports a destroyed mailbox as removed" => sub {
    my $doomed = $account->create_mailbox;

    my $q = $tester->request([[
      "Mailbox/query" => {},
    ]]);
    ok($q->is_success, "Mailbox/query") or diag explain $q->response_payload;

    my $qargs = $q->single_sentence("Mailbox/query")->arguments;
    my $query_state = $qargs->{queryState};
    ok(defined $query_state, 'got a queryState');
    ok(grep { $_ eq $doomed->id } @{ $qargs->{ids} // [] },
       'the mailbox is in the query results to start with');

    $tester->request([[
      "Mailbox/set" => { destroy => [ $doomed->id ] },
    ]]);

    my $qc = $tester->request([[
      "Mailbox/queryChanges" => { sinceQueryState => $query_state },
    ]]);
    ok($qc->is_success, "Mailbox/queryChanges") or diag explain $qc->response_payload;

    my $sent = $qc->single_sentence;
    if ($sent->name eq 'error') {
      is($sent->arguments->{type}, 'cannotCalculateChanges',
         'only cannotCalculateChanges is acceptable here');
      return;
    }

    # RFC 8620 S5.6 permits spurious removals, so don't assert exclusivity.
    ok(grep { $_ eq $doomed->id } @{ $sent->arguments->{removed} // [] },
       'the destroyed mailbox appears in removed')
      or diag explain $sent->arguments;

    ok(!(grep { $_->{id} && $_->{id} eq $doomed->id }
           @{ $sent->arguments->{added} // [] }),
       'and it is not also in added');
  };
};
