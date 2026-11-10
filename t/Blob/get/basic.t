use jmaptest;
use Digest::SHA qw(sha256);
use MIME::Base64 qw(encode_base64 decode_base64);
use Encode qw(encode);

# RFC 9404 Section 4.2: Blob/get returns blob octets as text or base64, with
# range selection, digests and the size of the whole blob.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:blob',
  );

  my $text = "The quick brown fox jumped over the lazy dog.";
  my $upload = $tester->upload({ accountId => $account->accountId, type => 'text/plain', blob => \$text });
  my $blobId = $upload->blobId;

  subtest "defaults: data and size" => sub {
    my $res = $tester->request([[ "Blob/get" => { ids => [ $blobId ] } ]]);
    ok($res->is_success, "Blob/get") or diag explain $res->response_payload;
    my $args = $res->single_sentence("Blob/get")->arguments;
    jcmp_deeply(
      $args,
      superhashof({
        list => [ superhashof({
          id            => jstr($blobId),
          'data:asText' => jstr($text),
          size          => jnum(length $text),
        }) ],
        notFound => [],
      }),
      "valid UTF-8 comes back as data:asText with the size",
    ) or diag explain $args;
    ok(!$args->{list}[0]{isTruncated}, "not truncated");
    ok(!$args->{list}[0]{isEncodingProblem}, "no encoding problem");
  };

  subtest "offset and length select a range; size is still the whole blob" => sub {
    my $res = $tester->request([[
      "Blob/get" => { ids => [ $blobId ], offset => 4, length => 5, properties => [ 'data:asText', 'data:asBase64', 'size' ] },
    ]]);
    my $item = $res->single_sentence("Blob/get")->arguments->{list}[0];
    is($item->{'data:asText'}, 'quick', "data:asText is the selected range");
    is($item->{'data:asBase64'}, encode_base64('quick', ''), "data:asBase64 is the same range");
    is($item->{size}, length $text, "size MUST always be the number of octets in the entire blob");
    ok(!$item->{isTruncated}, "a range inside the blob is not truncated");
  };

  subtest "a range past the end is truncated" => sub {
    my $res = $tester->request([[
      "Blob/get" => { ids => [ $blobId ], offset => 40, length => 100, properties => [ 'data:asText' ] },
    ]]);
    my $item = $res->single_sentence("Blob/get")->arguments->{list}[0];
    is($item->{'data:asText'}, substr($text, 40), "octets from the offset to the end are returned");
    ok($item->{isTruncated}, "isTruncated MUST be set when the range could not be fully satisfied");

    $res = $tester->request([[
      "Blob/get" => { ids => [ $blobId ], offset => 1000, properties => [ 'data:asText' ] },
    ]]);
    $item = $res->single_sentence("Blob/get")->arguments->{list}[0];
    is($item->{'data:asText'}, '', "an offset past the end gives an empty string");
    ok($item->{isTruncated}, "...and is truncated");
  };

  subtest "octets that are not UTF-8" => sub {
    my $bin = "\xff\xfe\x00binary";
    my $up = $tester->upload({ accountId => $account->accountId, type => 'application/octet-stream', blob => \$bin });
    my $res = $tester->request([[ "Blob/get" => { ids => [ $up->blobId ] } ]]);
    my $item = $res->single_sentence("Blob/get")->arguments->{list}[0];
    ok($item->{isEncodingProblem}, "isEncodingProblem MUST be true when data was requested and the octets are not UTF-8");
    is($item->{'data:asBase64'}, encode_base64($bin, ''), "data falls back to data:asBase64");
    ok(!exists $item->{'data:asText'} || !defined $item->{'data:asText'}, "no data:asText value for invalid UTF-8");

    $res = $tester->request([[ "Blob/get" => { ids => [ $up->blobId ], properties => [ 'data:asText' ] } ]]);
    $item = $res->single_sentence("Blob/get")->arguments->{list}[0];
    ok($item->{isEncodingProblem}, "explicit data:asText on binary: isEncodingProblem");
    # The text says null; the RFC's own example (G2's b1) omits the key.
    ok(!defined $item->{'data:asText'}, "data:asText MUST be null");

    # Cutting a multi-octet character in half is an encoding problem too.
    my $utf = encode('UTF-8', "caf\x{e9}!");
    $up = $tester->upload({ accountId => $account->accountId, type => 'text/plain', blob => \$utf });
    $res = $tester->request([[ "Blob/get" => { ids => [ $up->blobId ], offset => 0, length => 4, properties => [ 'data:asText' ] } ]]);
    $item = $res->single_sentence("Blob/get")->arguments->{list}[0];
    ok($item->{isEncodingProblem}, "truncating in the middle of a multi-octet sequence is an encoding problem");
  };

  subtest "digests" => sub {
    my $session = fetch_session($tester);
    my $caps = $session->{accounts}{ $account->accountId }{accountCapabilities}{'urn:ietf:params:jmap:blob'} // {};
    my @algs = @{ $caps->{supportedDigestAlgorithms} // [] };
    plan skip_all => "server advertises no digest algorithms" unless @algs;
    my ($alg) = grep { $_ eq 'sha-256' } @algs;
    plan skip_all => "server does not support sha-256 (has @algs)" unless $alg;
    my $res = $tester->request([[
      "Blob/get" => { ids => [ $blobId ], properties => [ 'digest:sha-256' ] },
    ]]);
    my $item = $res->single_sentence("Blob/get")->arguments->{list}[0];
    is($item->{'digest:sha-256'}, encode_base64(sha256($text), ''), "digest is the base64 of the digest of the octets");
    $res = $tester->request([[
      "Blob/get" => { ids => [ $blobId ], offset => 4, length => 5, properties => [ 'digest:sha-256' ] },
    ]]);
    $item = $res->single_sentence("Blob/get")->arguments->{list}[0];
    is($item->{'digest:sha-256'}, encode_base64(sha256('quick'), ''), "digest is calculated on the selected range");
  };

  subtest "unknown ids" => sub {
    my $res = $tester->request([[ "Blob/get" => { ids => [ 'nosuchblob-' . time(), $blobId ] } ]]);
    my $args = $res->single_sentence("Blob/get")->arguments;
    is(scalar @{ $args->{list} }, 1, "one found");
    is(scalar @{ $args->{notFound} }, 1, "one notFound");
  };
};
