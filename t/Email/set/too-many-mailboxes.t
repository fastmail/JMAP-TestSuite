use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  # RFC 8621 S1.3.1: maxMailboxesPerEmail is null for no limit, else >= 1.
  my $session = fetch_session($tester) or return;
  my $max = $session->{accounts}{ $account->accountId }{accountCapabilities}
              {'urn:ietf:params:jmap:mail'}{maxMailboxesPerEmail};
  unless (defined $max && $max <= 20) {
    plan skip_all => "maxMailboxesPerEmail is " . ($max // 'null') . "; not testing the limit";
  }

  my @mboxes  = map {; $account->create_mailbox } 0 .. $max;
  my %too_many = map {; $_->id => jtrue } @mboxes;
  my $message = $mboxes[0]->add_message({ subject => "too many mailboxes $$" });

  # RFC 8621 S4.6: "tooManyMailboxes": "The change to the set of Mailboxes
  # that this Email is in would exceed a server-defined maximum."
  my $res = $tester->request([[
    "Email/set" => {
      create => {
        new => {
          mailboxIds => \%too_many,
          subject    => "too many mailboxes create $$",
        },
      },
      update => {
        $message->id => { mailboxIds => \%too_many },
      },
    },
  ]]);

  my $args = $res->single_sentence('Email/set')->arguments;
  jcmp_deeply(
    $args->{notCreated},
    { new => superhashof({ type => 'tooManyMailboxes' }) },
    "create in maxMailboxesPerEmail + 1 mailboxes is rejected",
  ) or diag explain $res->as_stripped_triples;
  jcmp_deeply(
    $args->{notUpdated},
    { $message->id => superhashof({ type => 'tooManyMailboxes' }) },
    "update to maxMailboxesPerEmail + 1 mailboxes is rejected",
  ) or diag explain $res->as_stripped_triples;
};
