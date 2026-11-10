use jmaptest;
use MIME::Base64 qw(decode_base64);

# draft-ietf-jmap-blobext Section 8: Blob/convert. Each recipe family is only
# tested when the account advertises support for it.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:blob2',
  );

  my $session = fetch_session($tester);
  my $caps = $session->{accounts}{ $account->accountId }{accountCapabilities}{'urn:ietf:params:jmap:blob2'} // {};
  my $has = sub { my ($list, $type) = @_; grep { $_ eq $type } @{ $caps->{$list} // [] } };

  my $text = join('', map { "line $_\n" } 1 .. 100);
  my $up = $tester->upload({ accountId => $account->accountId, type => 'text/plain', blob => \$text });

  my $data_of = sub {
    my ($blobId) = @_;
    my $r = $tester->request([[ "Blob/get" => { ids => [ $blobId ], properties => [ 'data:asText', 'size' ] } ]]);
    return $r->single_sentence("Blob/get")->arguments->{list}[0];
  };

  subtest "compress and decompress" => sub {
    my ($type) = grep { $has->('supportedDecompressTypes', $_) } @{ $caps->{supportedCompressTypes} // [] };
    plan skip_all => "no compression type is both compressible and decompressible" unless $type;
    my $res = $tester->request([[
      "Blob/convert" => {
        create => {
          c => { compress   => { blobId => $up->blobId, type => $type } },
          d => { decompress => { blobId => '#c', type => $type } },
          a => { decompress => { blobId => '#c' } },          # type null: auto-detect
        },
      },
    ]]);
    ok($res->is_success, "Blob/convert") or diag explain $res->response_payload;
    my $args = $res->single_sentence("Blob/convert")->arguments;
    jcmp_deeply($args->{created}{c}, superhashof({ id => jstr(), type => jstr($type), size => jnum() }),
      "compressed blob has id, type and size") or diag explain $args;
    ok($args->{created}{d}, "decompress of a back-reference in the same call") or diag explain $args;
    is($data_of->($args->{created}{d}{id})->{'data:asText'}, $text, "decompression reproduces the original");
    # Section 8.6: with type null the server SHOULD auto-detect, and MUST say
    # unknownFormat if it can't.
    if (my $auto = $args->{created}{a}) {
      is($data_of->($auto->{id})->{'data:asText'}, $text, "format auto-detected when type is null");
    } else {
      jcmp_deeply($args->{notCreated}{a}, superhashof({ type => jstr('unknownFormat') }),
        "no auto-detection when type is null: unknownFormat") or diag explain $args;
    }

    $res = $tester->request([[
      "Blob/convert" => { create => { x => { compress => { blobId => $up->blobId, type => 'application/x-not-a-format' } } } },
    ]]);
    jcmp_deeply($res->single_sentence("Blob/convert")->arguments->{notCreated}{x},
      superhashof({ type => jstr('invalidProperties') }), "an unsupported type is invalidProperties");
    $res = $tester->request([[
      "Blob/convert" => { create => { x => { decompress => { blobId => $up->blobId } } } },
    ]]);
    jcmp_deeply($res->single_sentence("Blob/convert")->arguments->{notCreated}{x},
      superhashof({ type => jstr('unknownFormat') }), "undetectable data is unknownFormat");
  };

  subtest "archive and extract" => sub {
    my ($type) = grep { $has->('supportedExtractTypes', $_) } @{ $caps->{supportedArchiveTypes} // [] };
    plan skip_all => "no archive type is both creatable and extractable" unless $type;
    my $second = "second file\n";
    my $up2 = $tester->upload({ accountId => $account->accountId, type => 'text/plain', blob => \$second });
    my $res = $tester->request([[
      "Blob/convert" => {
        create => {
          ar => { archive => { type => $type, entries => [
            { name => 'site/', entryType => 'directory', modified => '2026-03-01T12:00:00Z' },
            { name => 'site/a.txt', blobId => $up->blobId,  modified => '2026-03-01T12:00:00Z', mode => '0644' },
            { name => 'site/b.txt', blobId => $up2->blobId, modified => '2026-02-15T09:30:00Z' },
          ] } },
          ex => { extract => { blobId => '#ar', type => $type } },
        },
      },
    ]]);
    ok($res->is_success, "Blob/convert") or diag explain $res->response_payload;
    my $args = $res->single_sentence("Blob/convert")->arguments;
    jcmp_deeply($args->{created}{ar}, superhashof({ id => jstr(), type => jstr($type), size => jnum() }),
      "archive created") or diag explain $args;
    my $ex = $args->{created}{ex} or return diag explain $args;
    my %by = map { $_->{name} => $_ } @{ $ex->{entries} // [] };
    ok($by{'site/a.txt'} && $by{'site/b.txt'}, "extract lists the file entries") or diag explain $ex;
    is($data_of->($by{'site/a.txt'}{blobId})->{'data:asText'}, $text, "an extracted entry's blob has the file content");
    is($data_of->($by{'site/b.txt'}{blobId})->{'data:asText'}, $second, "...for each file");
    is($by{'site/a.txt'}{modified}, '2026-03-01T12:00:00Z', "modified survives the round trip");
    ok(!$ex->{isIncomplete}, "a clean extraction is not isIncomplete");

    $res = $tester->request([[
      "Blob/convert" => { create => { x => { archive => { type => $type, entries => [ { name => 'f.txt' } ] } } } },
    ]]);
    jcmp_deeply($res->single_sentence("Blob/convert")->arguments->{notCreated}{x},
      superhashof({ type => jstr('invalidProperties') }), "a file entry without a blobId is invalidProperties");
  };

  subtest "delta and patch" => sub {
    my ($type) = grep { $has->('supportedPatchTypes', $_) } @{ $caps->{supportedDeltaTypes} // [] };
    plan skip_all => "no delta type is both producible and applicable" unless $type;
    (my $new_text = $text) =~ s/line 50\n/line fifty\n/;
    $new_text .= "line 101\n";
    my $up2 = $tester->upload({ accountId => $account->accountId, type => 'text/plain', blob => \$new_text });
    my $res = $tester->request([[
      "Blob/convert" => {
        create => {
          d => { delta => { blobId => $up->blobId, newBlobId => $up2->blobId, type => $type } },
          p => { patch => { blobId => $up->blobId, deltaBlobId => '#d', deltaType => $type } },
        },
      },
    ]]);
    ok($res->is_success, "Blob/convert") or diag explain $res->response_payload;
    my $args = $res->single_sentence("Blob/convert")->arguments;
    ok($args->{created}{d}, "delta created") or diag explain $args;
    ok($args->{created}{p}, "patch applied") or diag explain $args;
    is($data_of->($args->{created}{p}{id})->{'data:asText'}, $new_text, "patching the base with the delta reconstructs the new blob");

    # Only a text/x-diff carries context to notice the wrong base; rdiff and
    # bsdiff deltas apply blindly. Section 8 allows a partial result, marked
    # isIncomplete.
    return unless $type eq 'text/x-diff';
    $res = $tester->request([[
      "Blob/convert" => { create => { x => { patch => { blobId => $up2->blobId, deltaBlobId => $args->{created}{d}{id}, deltaType => $type } } } },
    ]]);
    my $x = $res->single_sentence("Blob/convert")->arguments;
    ok(
      ($x->{notCreated}{x} && $x->{notCreated}{x}{type} =~ /^(unknownFormat|conversionFailed)$/)
        || ($x->{created}{x} && $x->{created}{x}{isIncomplete}),
      "a diff applied to the wrong base fails or is isIncomplete",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "errors" => sub {
    # With no compress type to name, an unknown blobId could as well be
    # invalidProperties for the type.
    my ($compress_type) = @{ $caps->{supportedCompressTypes} // [] };
    my $res = $tester->request([[
      "Blob/convert" => {
        create => {
          ($compress_type
            ? (gone => { compress => { blobId => 'nosuchblob-' . time(), type => $compress_type } })
            : ()),
          none => { noPersist => jtrue() },
          two  => { compress => { blobId => $up->blobId, type => 'application/gzip' },
                    decompress => { blobId => $up->blobId } },
          c1   => { decompress => { blobId => '#c2' } },
          c2   => { decompress => { blobId => '#c1' } },
        },
      },
    ]]);
    ok($res->is_success, "Blob/convert") or diag explain $res->response_payload;
    my $nc = $res->single_sentence("Blob/convert")->arguments->{notCreated} // {};
    jcmp_deeply($nc->{gone}, superhashof({ type => jstr('notFound') }), "an unknown blobId is notFound")
      or diag explain $nc
      if $compress_type;
    ok($nc->{none}, "a request with no recipe fails");
    ok($nc->{two},  "a request with two recipes fails");
    for my $c (qw(c1 c2)) {
      jcmp_deeply($nc->{$c}, superhashof({ type => jstr('invalidProperties') }),
        "$c: every member of a dependency cycle MUST be rejected with invalidProperties") or diag explain $nc;
    }
  };
};
