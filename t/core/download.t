use jmaptest;
use URI::Escape qw(uri_escape);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
  );

  # First, grab our downloadUrl from the session resource
  my $data = fetch_session($tester) or return;

  my $download_url = $data->{downloadUrl};
  ok($download_url, 'got a download url');

  # RFC 8620 S2: downloadUrl "MUST contain variables called accountId,
  # blobId, type, and name".
  for my $var (qw(accountId blobId type name)) {
    like($download_url, qr/\{$var\}/, "downloadUrl has {$var}");
  }

  my $blob = $tester->upload({
    accountId => $account->accountId,
    type      => 'text/plain',
    blob      => \"foo"
  });
  my $id = $blob->blobId;

  # RFC 8620 S6.2: a level 1 URI Template (RFC 6570 S3.2.2), whose simple
  # expansion percent-encodes everything but unreserved characters.
  my %vars = (
    accountId => $account->accountId,
    blobId    => $id,
    type      => "text/plain",
    name      => "myfile.txt",
  );
  $download_url =~ s/\{(accountId|blobId|type|name)\}/uri_escape($vars{$1})/ge;

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

  # RFC 9110 S8.3.1: the media type is case-insensitive and may be followed
  # by parameters such as charset.
  my ($media_type) = split /\s*;/, $download_res->header('Content-Type') // '';
  is(lc $media_type, 'text/plain', 'good Content-Type');
  is($download_res->decoded_content, 'foo', 'download looks good');
  if (my $cd = $download_res->header('Content-Disposition')){
    note("Got a Content-Disposition header: $cd");

    # Either the plain quoted form or the RFC 5987 filename*= form is fine.
    like($cd, qr/filename="myfile\.txt"|filename\*=UTF-8''myfile\.txt/, 'filename is correct');
  }
};
