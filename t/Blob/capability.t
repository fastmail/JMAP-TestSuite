use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities('urn:ietf:params:jmap:core');

  my $session = fetch_session($tester) or return;
  $session = JSON::Typist->new->apply_types($session);

  my $acct_caps = $session->{accounts}{ $account->accountId }{accountCapabilities} // {};

  my $uint = all(jnum, code(sub { $_[0] == int $_[0] && $_[0] >= 0 }));

  # RFC 9404 S3.1 and draft-ietf-jmap-blobext S2.1: the account value "MUST
  # contain" these, and "Servers MUST allow at least 64 DataSourceObjects".
  my %want = (
    maxSizeBlobSet            => any(undef, $uint),
    maxDataSources            => all($uint, code(sub { $_[0] >= 64 || (0, "$_[0] is below 64") })),
    supportedTypeNames        => array_each(jstr),
    supportedDigestAlgorithms => array_each(jstr),
  );

  my %extra = (
    'urn:ietf:params:jmap:blob'  => {},
    'urn:ietf:params:jmap:blob2' => {
      uploadUrl => any(undef, jstr),
      chunkSize => any(undef, $uint),
      (map {; $_ => any(undef, array_each(jstr)) } qw(
        supportedImageReadTypes supportedImageWriteTypes
        supportedArchiveTypes supportedExtractTypes
        supportedCompressTypes supportedDecompressTypes
        supportedDeltaTypes supportedPatchTypes
      )),
    },
  );

  my $tested = 0;
  for my $uri (sort keys %extra) {
    my $in_session = exists $session->{capabilities}{$uri};
    my $in_account = exists $acct_caps->{$uri};
    next unless $in_session || $in_account;
    $tested++;

    subtest $uri => sub {
      # RFC 9404 S3.1: a server listing it for an account "MUST also include
      # the property in the capabilities property", with "an empty object".
      ok($in_session, "advertised in the session capabilities") or return;
      jcmp_deeply($session->{capabilities}{$uri}, {}, "session value is an empty object");

      unless ($in_account) {
        note("not advertised for this account");
        return;
      }

      jcmp_deeply(
        $acct_caps->{$uri},
        superhashof({ %want, %{ $extra{$uri} } }),
        "account value has the required properties",
      ) or diag explain $acct_caps->{$uri};

      # draft-ietf-jmap-blobext S2.1: these are given only "If supplied".
      for my $limit (qw(maxConvertSize maxArchiveEntries maxImageDimension)) {
        next unless $uri =~ /blob2/ && exists $acct_caps->{$uri}{$limit};
        jcmp_deeply($acct_caps->{$uri}{$limit}, any(undef, $uint), "$limit is an UnsignedInt or null");
      }
    };
  }

  plan skip_all => "server advertises neither blob capability" unless $tested;
};
