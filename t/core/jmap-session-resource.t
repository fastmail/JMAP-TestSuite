use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;
  my $res = $tester->ua->get($tester->api_uri);
  ok($res->is_success, "GET " . $tester->api_uri);

  my $data = eval { decode_json($res->decoded_content) };
  ok($data, 'Got JSON response')
    or diag("Invalid json?: " . $res->decoded_content);

  my $typed = JSON::Typist->new->apply_types($data);

  jcmp_deeply(
    $typed,
    {
      username => jstr,
      accounts => {
        $account->accountId => superhashof({
          name => jstr,
          isPrimary => jbool,
          isReadOnly => jbool,
        }),
      },
      capabilities => superhashof({
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
