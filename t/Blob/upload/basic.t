use jmaptest;
use MIME::Base64 qw(encode_base64);

# RFC 9404 Section 4.1: Blob/upload creates blobs from DataSourceObjects.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:blob',
  );

  subtest "inline text and base64 sources" => sub {
    # RFC 8620 Section 3.4: createdIds is "only returned if given in the
    # request", so send one to see the entries RFC 9404 says every upload gets.
    my $res = $tester->request({
      createdIds  => {},
      methodCalls => [[
        "Blob/upload" => {
          create => {
            t => { data => [ { 'data:asText' => "Hello, world!" } ], type => 'text/plain' },
            b => { data => [ { 'data:asBase64' => encode_base64("\x00\x01\x02binary", '') } ] },
            e => { data => [] },
          },
        }, 'a',
      ]],
    });
    ok($res->is_success, "Blob/upload") or diag explain $res->response_payload;
    my $args = $res->single_sentence("Blob/upload")->arguments;

    # The created objects contain id, type and size.
    jcmp_deeply(
      $args->{created}{t},
      superhashof({ id => jstr(), type => jstr('text/plain'), size => jnum(13) }),
      "text source: id, the given type, and the octet count",
    ) or diag explain $args;
    jcmp_deeply(
      $args->{created}{b},
      superhashof({ id => jstr(), size => jnum(9) }),
      "base64 source decoded to its octets",
    ) or diag explain $args;
    jcmp_deeply(
      $args->{created}{e},
      superhashof({ id => jstr(), size => jnum(0) }),
      "zero data sources make an empty blob",
    ) or diag explain $args;
    ok(!$args->{notCreated}, "nothing failed") or diag explain $args->{notCreated};

    # RFC 9404 Section 4.1: "For each successful upload, servers MUST add an
    # entry to the createdIds map", so with one in the request it comes back.
    my $created_ids = ($res->wrapper_properties // {})->{createdIds} // {};
    is($created_ids->{t}, $args->{created}{t}{id}, "creation id t is in createdIds");
  };

  subtest "concatenation, blobId sources with offset and length, and a back-reference" => sub {
    my $res = $tester->request([
      [ "Blob/upload" => { create => { b4 => { data => [ { 'data:asText' => "The quick brown fox jumped over the lazy dog." } ] } } }, 'S4' ],
      [ "Blob/upload" => { create => { cat => { data => [
            { 'data:asText' => "How" },
            { blobId => '#b4', length => 7, offset => 3 },
            { 'data:asText' => "was t" },
            { blobId => '#b4', length => 1, offset => 1 },
            { 'data:asBase64' => "YXQ/" },
          ] } } }, 'CAT' ],
      [ "Blob/get" => { ids => ['#cat'], properties => [ 'data:asText', 'size' ] }, 'G4' ],
    ]);
    ok($res->is_success, "request") or diag explain $res->response_payload;
    my $got = $res->sentence(2)->arguments;
    jcmp_deeply(
      $got->{list},
      [ superhashof({ 'data:asText' => jstr("How quick was that?"), size => jnum(19) }) ],
      "sources concatenate in order, ranges honoured (the RFC 9404 Section 4.1.2 example)",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "invalid sources are rejected, not guessed at" => sub {
    my $res = $tester->request([[
      "Blob/upload" => {
        create => {
          bad64 => { data => [ { 'data:asBase64' => 'not*base64!' } ] },
          range => { data => [ { 'data:asText' => 'short' } ] },
        },
      },
    ], [
      "Blob/upload" => {
        create => {
          past => { data => [ { blobId => '#range', offset => 100, length => 1 } ] },
          long => { data => [ { blobId => '#range', offset => 0, length => 50 } ] },
          none => { data => [ { blobId => 'nosuchblob-' . time() } ] },
          two  => { data => [ { 'data:asText' => 'a', 'data:asBase64' => 'YQ==' } ] },
        },
      },
    ]]);
    ok($res->is_success, "request") or return diag explain $res->response_payload;
    my $a1 = $res->sentence(0)->arguments;
    my $a2 = $res->sentence(1)->arguments;
    ok($a1->{notCreated}{bad64}, "invalid base64 MUST result in a notCreated response") or diag explain $a1;
    ok($a1->{created}{range}, "the valid creation in the same call succeeds");
    ok($a2->{notCreated}{past}, "a range that begins past the end of the blob is invalid") or diag explain $a2;
    ok($a2->{notCreated}{long}, "a range that extends past the end of the blob is invalid") or diag explain $a2;
    ok($a2->{notCreated}{none}, "an unknown blobId is a notCreated response") or diag explain $a2;
    ok($a2->{notCreated}{two},  "a source with two data properties is rejected") or diag explain $a2;
    for my $cid (qw(past long none two)) {
      jcmp_deeply($a2->{notCreated}{$cid}, superhashof({ type => jstr() }), "$cid has a SetError type")
        if $a2->{notCreated}{$cid};
    }
  };
};
