use jmaptest;

my $MAIL = 'urn:ietf:params:jmap:mail';

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;
  my $data = fetch_session($tester) or return;

  my $typed = JSON::Typist->new->apply_types($data);

  # RFC 8620 S2: other Session properties MAY be included, and the client
  # MUST ignore capability properties it does not understand.
  jcmp_deeply(
    $typed,
    superhashof({
      username => jstr,
      # The user may also see other (e.g. shared) accounts.
      accounts => superhashof({
        $account->accountId => superhashof({
          name => jstr,
          isPersonal => jbool,
          isReadOnly => jbool,
          # RFC 8620 §2 lists only capabilities with account-scoped methods
          # here; its own example omits urn:ietf:params:jmap:core.
          accountCapabilities => superhashof({}),
        }),
      }),
      capabilities => superhashof({
        'urn:ietf:params:jmap:core' => superhashof({
          maxSizeUpload => jnum,
          maxConcurrentUpload => jnum,
          maxSizeRequest => jnum,
          maxConcurrentRequests => jnum,
          maxCallsInRequest => jnum,
          maxObjectsInGet => jnum,
          maxObjectsInSet => jnum,
          collationAlgorithms => ignore(),
        }),
      }),
      primaryAccounts => superhashof({}),
      apiUrl => jstr,
      downloadUrl => jstr,
      uploadUrl => jstr,
      state => jstr,
      eventSourceUrl => jstr,
    }),
    'Response looks good',
  ) or diag explain $data;

  return unless exists $typed->{capabilities}{$MAIL};

  subtest "mail capability" => sub {
    jcmp_deeply(
      $typed->{accounts}{ $account->accountId }{accountCapabilities}{$MAIL},
      superhashof({
        maxMailboxesPerEmail => any(jnum, undef),
        maxMailboxDepth => any(jnum, undef),
        maxSizeMailboxName => jnum,
        maxSizeAttachmentsPerEmail => jnum,
        emailQuerySortOptions => superbagof(),
        mayCreateTopLevelMailbox => jbool,
      }),
      'mail account capability looks good',
    ) or diag explain $data;

    # RFC 8620 S2: there "MAY be no entry" in primaryAccounts for a
    # capability the server supports.
    my $primary = $typed->{primaryAccounts}{$MAIL};
    ok(!defined $primary || exists $typed->{accounts}{$primary},
       'primary mail account, if any, is one of the accounts')
      or diag explain $data;
  };
};
