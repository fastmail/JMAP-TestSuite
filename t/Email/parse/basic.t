use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $subject = "parse me $$";
  my $message = $account->email_blob(generic => {
    from    => 'sender@example.com',
    subject => $subject,
    body    => "parsed body $$",
  });
  ok($message->is_success, 'uploaded a message');
  my $blob_id = $message->blobId;

  subtest "a message blob is parsed" => sub {
    my $res = $tester->request([[
      "Email/parse" => {
        blobIds    => [ $blob_id ],
        properties => [ qw(id mailboxIds keywords receivedAt subject from bodyValues textBody) ],
        fetchTextBodyValues => jtrue,
      },
    ]]);

    my $args = $res->single_sentence('Email/parse')->arguments;
    jcmp_deeply(
      $args,
      {
        accountId   => $account->accountId,
        parsed      => { $blob_id => ignore() },
        notParsable => undef,
        notFound    => undef,
      },
      "response has exactly the S4.9 arguments, the blob in parsed",
    ) or diag explain $res->as_stripped_triples;

    my $email = $args->{parsed}{$blob_id};
    ok($email, "the blob was parsed") or return;
    my $part_id = $email->{textBody}[0]{partId} // '';

    # RFC 8621 S4.9: "The following metadata properties on the Email objects
    # will be null if requested: id, mailboxIds, keywords, receivedAt".
    jcmp_deeply(
      $email,
      {
        id         => undef,
        mailboxIds => undef,
        keywords   => undef,
        receivedAt => undef,
        subject    => $subject,
        from       => [ { name => undef, email => 'sender@example.com' } ],
        textBody   => [ superhashof({ partId => $part_id, type => 'text/plain' }) ],
        bodyValues => { $part_id => superhashof({ value => "parsed body $$" }) },
      },
      "parsed email has the message's content and null metadata",
    ) or diag explain $email;
  };

  subtest "an unknown blob is notFound" => sub {
    my $missing = "no-such-blob-$$";
    my $res = $tester->request([[
      "Email/parse" => { blobIds => [ $missing ] },
    ]]);

    my $args = $res->single_sentence('Email/parse')->arguments;
    jcmp_deeply($args->{notFound}, [ $missing ], "blob is in notFound")
      or diag explain $res->as_stripped_triples;
    ok(! $args->{parsed}, "nothing was parsed") or diag explain $args;
  };

  subtest "a non-message blob is not parsed as an email" => sub {
    my $upload = $tester->upload({
      accountId => $account->accountId,
      type      => 'application/octet-stream',
      blob      => \join('', map {; chr } 0 .. 255),
    });
    ok($upload->is_success, 'uploaded a binary blob');
    my $id = $upload->blobId;

    my $res = $tester->request([[
      "Email/parse" => { blobIds => [ $id ] },
    ]]);

    # RFC 8621 S4.9: notParsable lists blobs "that could not be parsed as
    # Emails"; a lenient parser may still make an Email of arbitrary octets.
    my $args = $res->single_sentence('Email/parse')->arguments;
    my @where = grep {;
        $_ eq 'parsed' ? exists(($args->{parsed} // {})->{$id})
                       : grep {; $_ eq $id } @{ $args->{$_} // [] }
      } qw(parsed notParsable notFound);
    cmp_deeply("@where", any('parsed', 'notParsable'), "blob is in exactly one of parsed or notParsable")
      or diag explain $res->as_stripped_triples;
    note("server reported the binary blob as @where");
  };
};
