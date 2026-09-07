use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;
  my $data = fetch_session($tester) or return;

  my $typed = JSON::Typist->new->apply_types($data);

  jcmp_deeply(
    $typed,
    {
      username => jstr,
      accounts => {
        $account->accountId => superhashof({
          name => jstr,
          isPersonal => jbool,
          isReadOnly => jbool,
          # RFC 8620 §2 lists only capabilities with account-scoped methods
          # here; its own example omits urn:ietf:params:jmap:core.
          accountCapabilities => superhashof({
            'urn:ietf:params:jmap:mail' => {
              maxMailboxesPerEmail => any(jnum, undef),
              maxMailboxDepth => any(jnum, undef),
              maxSizeMailboxName => jnum,
              maxSizeAttachmentsPerEmail => jnum,
              emailQuerySortOptions => superbagof(),
              mayCreateTopLevelMailbox => jbool,
            },
          }),
        }),
      },
      capabilities => superhashof({
        'urn:ietf:params:jmap:mail' => {},
        'urn:ietf:params:jmap:core' => {
          maxSizeUpload => jnum,
          maxConcurrentUpload => jnum,
          maxSizeRequest => jnum,
          maxConcurrentRequests => jnum,
          maxCallsInRequest => jnum,
          maxObjectsInGet => jnum,
          maxObjectsInSet => jnum,
          collationAlgorithms => ignore(),
        },
      }),
      primaryAccounts => superhashof({
        'urn:ietf:params:jmap:mail' => $account->accountId,
      }),
      apiUrl => jstr,
      downloadUrl => jstr,
      uploadUrl => jstr,
      state => jstr,
      eventSourceUrl => jstr,
    },
    'Response looks good',
  ) or diag explain $data;
};
