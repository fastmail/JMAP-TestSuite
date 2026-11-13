use jmaptest;
use Digest::SHA ();
use MIME::Base64 qw(decode_base64);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my %advertised = map {; $_ => 1 } @{ $tester->default_using // [] };
  $tester->require_capabilities('urn:ietf:params:jmap:core');

  my @caps = grep {; $advertised{$_} } qw(urn:ietf:params:jmap:blob urn:ietf:params:jmap:blob2);
  plan skip_all => "server advertises neither blob capability" unless @caps;

  my $session = fetch_session($tester) or return;

  my $content = "hello world";
  my $blob = $tester->upload({
    accountId => $account->accountId,
    type      => 'application/octet-stream',
    blob      => \$content,
  });

  my %digest_of = (
    'sha'     => \&Digest::SHA::sha1,
    'sha-256' => \&Digest::SHA::sha256,
    'sha-512' => \&Digest::SHA::sha512,
  );

  # RFC 9404 S4.2: isTruncated has "default: false".
  my $not_truncated = code(sub { !$_[0]{isTruncated} || (0, "isTruncated is true") });

  for my $cap (@caps) {
    my $algs = $session->{accounts}{ $account->accountId }{accountCapabilities}{$cap}
                 {supportedDigestAlgorithms} // [];

    my $get = sub {
      my ($args) = @_;
      my $res = $tester->request({
        using       => [ 'urn:ietf:params:jmap:core', $cap ],
        methodCalls => [[ "Blob/get" => { ids => [ $blob->blobId ], %$args } ]],
      });
      ok($res->is_success, "Blob/get") or diag(explain($res->response_payload)), return;
      return $res->single_sentence;
    };

    subtest "$cap: length 0" => sub {
      my $s = $get->({ offset => 0, length => 0, properties => [ 'data:asText', 'size' ] }) or return;
      jcmp_deeply(
        $s->arguments->{list},
        [ all(superhashof({ 'data:asText' => '', size => jnum(length $content) }), $not_truncated) ],
        "empty range is the empty string and not truncated",
      ) or diag explain $s->as_stripped_pair;
    };

    # RFC 9404 S4.2: with no length, isTruncated "is not given unless the
    # start offset is past the end of the blob".
    subtest "$cap: offset at the end, no length" => sub {
      my $s = $get->({ offset => length $content, properties => [ 'data:asText', 'size' ] }) or return;
      jcmp_deeply(
        $s->arguments->{list},
        [ all(superhashof({ 'data:asText' => '', size => jnum(length $content) }), $not_truncated) ],
        "range at the end is the empty string and not truncated",
      ) or diag explain $s->as_stripped_pair;
    };

    my ($alg) = grep {; $digest_of{$_} } @$algs;
    if ($alg) {
      # RFC 9404 S4.2: the digest is "of the octets in the selected range".
      subtest "$cap: digest:$alg of a range" => sub {
        my $s = $get->({ offset => 2, length => 5, properties => [ "digest:$alg" ] }) or return;
        my $got = $s->arguments->{list}[0]{"digest:$alg"};
        ok(defined $got, "digest returned") or diag(explain($s->as_stripped_pair)), return;
        is(
          unpack('H*', decode_base64("$got")),
          unpack('H*', $digest_of{$alg}->(substr $content, 2, 5)),
          "digest is of the selected octets",
        );
      };
    }

    # RFC 9404 S4.2: only advertised algorithms are properties; RFC 8620 S5.1:
    # requesting "an invalid property" is invalidArguments.
    my %supported = map {; $_ => 1 } @$algs;
    my ($unsupported) = grep {; !$supported{$_} } qw(md5 unknown-digest);
    subtest "$cap: digest:$unsupported is not advertised" => sub {
      my $s = $get->({ properties => [ "digest:$unsupported" ] }) or return;
      jcmp_deeply(
        $s->as_stripped_pair,
        [ error => superhashof({ type => 'invalidArguments' }) ],
        "invalidArguments",
      ) or diag explain $s->as_stripped_pair;
    };
  }
};
