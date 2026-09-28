use jmaptest;

# Email/import gives the created email its own blobId.  Both it and the
# uploaded blob must stay downloadable, and the upload byte-identical.

attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $time = time;
  my $raw = <<"EOF";
From: "Some Example Sender" <example\@example.com>\r
To: directions-of-responsibility\@adipiscialiquam.org\r
Subject: test message\r
Date: Wed, 7 Dec 2016 01:48:15 -0500\r
MIME-Version: 1.0\r
Content-Type: text/plain; charset="UTF-8"\r
X-Unique: $time $$\r
\r
This is a test message.\r
EOF

  my $up = $tester->upload({
    accountId => $account->accountId,
    type      => 'message/rfc822',
    blob      => \$raw,
  });
  ok($up->is_success, 'upload succeeded')
    or diag explain $up->http_response->as_string;

  my $account_id = $up->payload->{accountId};
  my $blob_id    = $up->payload->{blobId};
  ok($account_id, 'got accountId from upload');
  ok($blob_id,    'got blobId from upload') or return;

  subtest "the uploaded blob downloads unchanged" => sub {
    my $res = $tester->download({
      accountId => $account_id,
      blobId    => $blob_id,
      name      => 'message.eml',
    });
    ok($res->is_success, 'download succeeded');
    is(${ $res->bytes_ref }, $raw, 'bytes match what was uploaded');
  };

  my $mailbox = $account->create_mailbox;

  my $res = $tester->request([[
    "Email/import" => {
      emails => {
        1 => {
          blobId     => $blob_id,
          mailboxIds => { $mailbox->id => jtrue() },
        },
      },
    },
  ]]);
  ok($res->is_success, 'Email/import succeeded')
    or diag explain $res->response_payload;

  my $created = $res->single_sentence('Email/import')->arguments->{created}{1};
  ok($created, 'the email was imported') or return;

  my $new_blob_id = $created->{blobId};
  ok($new_blob_id, 'the imported email has a blobId');

  subtest "the original blob still downloads unchanged" => sub {
    my $res = $tester->download({
      accountId => $account_id,
      blobId    => $blob_id,
      name      => 'message.eml',
    });
    ok($res->is_success, 'download succeeded');
    is(${ $res->bytes_ref }, $raw, 'bytes still match');
  };

  subtest "the imported email's own blob downloads" => sub {
    my $res = $tester->download({
      accountId => $account_id,
      blobId    => $new_blob_id,
      name      => 'message.eml',
    });
    ok($res->is_success, 'download succeeded')
      or diag explain $res->http_response->as_string;

    # Not byte-compared: a server may add trace headers on delivery.
    my $got = ${ $res->bytes_ref };
    like($got, qr/Subject: test message/, 'has the original subject');
    like($got, qr/\QX-Unique: $time $$\E/, 'is this run\'s message');
  };
};
