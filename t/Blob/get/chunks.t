use jmaptest;
use Digest::SHA qw(sha256);
use MIME::Base64 qw(encode_base64);

# draft-ietf-jmap-blobext Section 5: the chunks property describes how a blob
# is stored; concatenating the described ranges rebuilds the blob.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:blob2',
  );

  my $text = join('', map { "line $_ of the blob\n" } 1 .. 200);

  my $session = fetch_session($tester);
  my $caps = $session->{accounts}{ $account->accountId }{accountCapabilities}{'urn:ietf:params:jmap:blob2'} // {};
  my $sha256 = grep { $_ eq 'sha-256' } @{ $caps->{supportedDigestAlgorithms} // [] };
  my $up = $tester->upload({ accountId => $account->accountId, type => 'text/plain', blob => \$text });

  my $res = $tester->request([[
    "Blob/get" => {
      ids => [ $up->blobId ],
      properties => [ 'size', 'chunks' ],
      dataSourceProperties => [ 'blobId', 'size', 'offset', 'length', 'position', 'digest:sha-256' ],
    },
  ]]);
  ok($res->is_success, "Blob/get chunks") or diag explain $res->response_payload;
  my $item = $res->single_sentence("Blob/get")->arguments->{list}[0];
  is($item->{size}, length $text, "size of the whole blob");
  my $chunks = $item->{chunks};
  ok(ref $chunks eq 'ARRAY' && @$chunks >= 1, "chunks is an array of one or more DataSourceObjects")
    or return diag explain $item;

  # Section 3: size, position and digest:* are optional in a chunk, but
  # correct when present. A null length runs to the end of the source.
  my $rebuilt = '';
  my $pos = 0;
  for my $c (@$chunks) {
    is($c->{position}, $pos, "chunk position is where the previous chunk ended")
      if defined $c->{position};
    my $get = $tester->request([[
      "Blob/get" => { ids => [ $c->{blobId} ], offset => $c->{offset}, length => $c->{length}, properties => [ 'data:asText', 'size' ] },
    ]]);
    my $part = $get->single_sentence("Blob/get")->arguments->{list}[0];
    is($part->{size}, $c->{size}, "chunk size is the size of the chunk's blob")
      if defined $c->{size};
    is($c->{'digest:sha-256'}, encode_base64(sha256($part->{'data:asText'}), ''),
       "chunk digest covers the octets the chunk contributes")
      if $sha256 && defined $c->{'digest:sha-256'};
    $rebuilt .= $part->{'data:asText'};
    $pos += length $part->{'data:asText'};
  }
  is($rebuilt, $text, "concatenating the chunks' ranges reproduces the blob");
};
