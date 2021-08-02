use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  # First, grab our downloadUrl
  my $res = $tester->ua->lwp->get($tester->api_uri);
  ok($res->is_success, "GET " . $tester->api_uri);

  my $data = eval { decode_json($res->decoded_content) };
  ok($data, 'Got JSON response')
    or diag("Invalid json?: " . $res->decoded_content);

  my $download_url = $data->{downloadUrl};
  ok($download_url, 'got a download url');

  my $account_id = $account->accountId;

  if ($download_url =~ s/{accountId}/$account_id/) {
    note("downloadUrl included {accountId} variable. Using $download_url");
  }

  if ($download_url =~ s/{name}/myfile.txt/) {
    note("downloadUrl included {name} variable. Using $download_url");
  }

  my $blob = $tester->upload({
    accountId => $account->accountId,
    type      => 'text/plain',
    blob      => \"foo"
  });
  my $id = $blob->blobId;

  ok($download_url =~ s/{blobId}/$id/, 'downloadUrl included a blobId');

  ok($download_url =~ s:{type}:text/plain:, 'downloadUrl included a blobId');

  # XXX - downloadUrl should probably be required to be an absolute url
  unless ($download_url =~ /^http/i) {
    my $base = $tester->api_uri;
    $base =~ s{^(.*?//.*?)/.*}{$1};

    $download_url = $base . $download_url;
  }

  my $download_res = $tester->ua->lwp->get($download_url,
    $tester->_maybe_auth_header,
  );

  ok($download_res->is_success, 'downloaded a file');

  is($download_res->header('Content-Type'), 'text/plain', 'good Content-Type');
  is($download_res->decoded_content, 'foo', 'download looks good');
  if (my $cd = $download_res->header('Content-Disposition')){
    note("Got a Content-Disposition header: $cd");

    like($cd, qr/filename="myfile.txt"/, 'filename is correct');
  }
};
