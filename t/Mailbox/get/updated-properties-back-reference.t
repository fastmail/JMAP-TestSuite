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
  my $state   = $account->get_state('mailbox');

  $mailbox->add_message;

  # RFC 8621 S2.2: "The 'updatedProperties' array may be used directly via
  # a back-reference in a subsequent 'Mailbox/get' call in the same request".
  my $res = $tester->request([
    [ "Mailbox/changes" => { sinceState => $state }, 'changes' ],
    [ "Mailbox/get" => {
        '#ids' => {
          resultOf => 'changes', name => 'Mailbox/changes', path => '/updated',
        },
        '#properties' => {
          resultOf => 'changes', name => 'Mailbox/changes', path => '/updatedProperties',
        },
      }, 'get' ],
  ]);
  ok($res->is_success, "request with back-references")
    or diag explain $res->response_payload;

  my $changes = $res->sentence_named("Mailbox/changes")->arguments;
  my $get     = $res->sentence_named("Mailbox/get")->arguments;

  # The back-references resolve, rather than giving invalidResultReference.
  ok($get->{list}, "Mailbox/get ran") or diag explain $res->as_stripped_triples;

  ok(
    (grep { $_ eq $mailbox->id } @{ $changes->{updated} }),
    "our Mailbox is updated",
  ) or diag explain $changes;

  my ($got) = grep { $_->{id} eq $mailbox->id } @{ $get->{list} // [] };
  ok($got, "Mailbox/get returned our Mailbox") or diag explain $get;

  my $props = $changes->{updatedProperties};
  if (defined $props) {
    # RFC 8621 S2.2: non-null only if nothing but the four counts changed,
    # listing "the properties that may have changed".
    jcmp_deeply(
      $props,
      all(
        subsetof(qw(totalEmails unreadEmails totalThreads unreadThreads)),
        supersetof('totalEmails'),
      ),
      "updatedProperties lists only counts, including totalEmails",
    );
    is_deeply(
      [ sort keys %{ $got // {} } ],
      [ sort map {; "$_" } 'id', @$props ],
      "Mailbox/get returned only id and the updated properties",
    );
  }

  is($got && $got->{totalEmails}, 1, "totalEmails reflects the new Email");
};
