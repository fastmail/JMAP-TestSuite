use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  # First, grab our uploadUrl
  my $res = $tester->ua->get($tester->api_uri);
  ok($res->is_success, "GET " . $tester->api_uri);

  my $data = eval { decode_json($res->decoded_content) };
  ok($data, 'Got JSON response')
    or diag("Invalid json?: " . $res->decoded_content);

  my $upload_url = $data->{uploadUrl};
  ok($upload_url, 'got an upload url');

  my $account_id = $account->accountId;

  if ($upload_url =~ s/{accountId}/$account_id/) {
    note("uploadUrl included {accountId} variable. Using $upload_url");
  }

  # XXX - uploadUrl should probably be required to be an absolute url
  unless ($upload_url =~ /^http/i) {
    my $base = $tester->api_uri;
    $base =~ s{^(.*?//.*?)/.*}{$1};

    $upload_url = $base . $upload_url;
  }

  my $upload_res = $tester->ua->post($upload_url,
    'Content-Type' => 'text/plain',
    $tester->_maybe_auth_header,
    Content => "foo",
  );

  ok($upload_res->is_success, 'uploaded a file');

  my $upload_data = eval { decode_json($upload_res->decoded_content) };
  ok($upload_data, 'Got JSON response')
    or diag("Invalid json?: " . $res->decoded_content);

  my $typed = JSON::Typist->new->apply_types($upload_data);

  jcmp_deeply(
    $typed,
    superhashof({ # XXX - Strict response check instead?
      accountId => jstr($account_id),
      blobId    => jstr(),
      type      => 'text/plain',
      size      => jnum(3),
    }),
    'upload response looks good',
  );
};
