use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mdn',
    'urn:ietf:params:jmap:mail',
  );

  # Build a minimal MDN (multipart/report with message/disposition-notification)
  my $mdn_text = join("\r\n",
    'From: tester@example.com',
    'To: sender@example.com',
    'Subject: Read: Test Message',
    'MIME-Version: 1.0',
    'Content-Type: multipart/report; report-type=disposition-notification;',
    '  boundary="=_mdn_boundary"',
    '',
    '--=_mdn_boundary',
    'Content-Type: text/plain; charset=utf-8',
    '',
    'This is a Message Disposition Notification.',
    '',
    '--=_mdn_boundary',
    'Content-Type: message/disposition-notification',
    '',
    'Reporting-UA: Test Client',
    'Final-Recipient: rfc822;tester@example.com',
    'Original-Message-ID: <original@example.com>',
    'Disposition: manual-action/mdn-sent-manually;displayed',
    '',
    '--=_mdn_boundary--',
    '',
  );

  my $upload = $tester->upload({
    accountId => $account->accountId,
    type      => 'message/rfc822',
    blob      => \$mdn_text,
  });
  ok($upload->is_success, "uploaded MDN blob") or diag explain $upload;

  my $blob_id = $upload->blobId;

  subtest "parse valid MDN blob" => sub {
    my $res = $tester->request([[
      "MDN/parse" => {
        blobIds => [$blob_id],
      },
    ]]);
    ok($res->is_success, "MDN/parse") or diag explain $res->response_payload;

    my $args = $res->single_sentence("MDN/parse")->arguments;

    ok(!$args->{notFound},    "nothing not found");
    ok(!$args->{notParsable}, "nothing not parsable") or diag explain $args->{notParsable};
    ok($args->{parsed}{$blob_id}, "blob was parsed") or diag explain $args;

    my $mdn = $args->{parsed}{$blob_id};
    jcmp_deeply(
      $mdn,
      superhashof({
        subject     => jstr(),
        disposition => superhashof({
          actionMode  => jstr(),
          sendingMode => jstr(),
          type        => jstr(),
        }),
      }),
      "parsed MDN has required fields",
    ) or diag explain $mdn;
  };

  subtest "not-found blob id returns notFound" => sub {
    my $res = $tester->request([[
      "MDN/parse" => {
        blobIds => ['nonexistent-blob-id'],
      },
    ]]);
    ok($res->is_success, "MDN/parse with unknown blob");

    my $args = $res->single_sentence("MDN/parse")->arguments;
    ok($args->{notFound}, "nonexistent id in notFound");
    is($args->{notFound}[0], 'nonexistent-blob-id', "correct id reported");
  };

  subtest "non-MDN blob returns notParsable" => sub {
    my $plain_text = "This is not an MDN.\r\n";
    my $up2 = $tester->upload({
      accountId => $account->accountId,
      type      => 'text/plain',
      blob      => \$plain_text,
    });
    ok($up2->is_success, "uploaded plain text blob");

    my $res = $tester->request([[
      "MDN/parse" => {
        blobIds => [$up2->blobId],
      },
    ]]);
    ok($res->is_success, "MDN/parse with plain text blob");

    my $args = $res->single_sentence("MDN/parse")->arguments;
    ok($args->{notParsable}, "plain text blob is notParsable");
  };
};
