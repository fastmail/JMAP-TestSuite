use jmaptest;

# RFC 9404 Section 4.3: Blob/lookup finds the objects of each named type that
# reference a blob.

attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
    'urn:ietf:params:jmap:blob',
  );

  my $session = fetch_session($tester);
  my $caps = $session->{accounts}{ $account->accountId }{accountCapabilities}{'urn:ietf:params:jmap:blob'} // {};
  my %supported = map { $_ => 1 } @{ $caps->{supportedTypeNames} // [] };
  plan skip_all => "server does not support Blob/lookup (supportedTypeNames is empty)"
    unless %supported;

  my $mailbox = $account->create_mailbox;
  my $email   = $mailbox->add_message;
  my @types   = grep { $supported{$_} } qw(Email Thread Mailbox);
  plan skip_all => "server supports none of Email, Thread, Mailbox for lookup" unless @types;

  subtest "an email's blob" => sub {
    my $res = $tester->request([[
      "Blob/lookup" => { typeNames => \@types, ids => [ $email->blobId ] },
    ]]);
    ok($res->is_success, "Blob/lookup") or diag explain $res->response_payload;
    my $args = $res->single_sentence("Blob/lookup")->arguments;
    my ($info) = grep { $_->{id} eq $email->blobId } @{ $args->{list} // [] };
    ok($info, "a BlobInfo for the blob") or return diag explain $args;
    my %expect = (
      Email   => [ $email->id ],
      Thread  => [ $email->threadId ],
      Mailbox => bag(keys %{ $email->mailboxIds }),
    );
    for my $t (@types) {
      jcmp_deeply($info->{matchedIds}{$t}, $expect{$t}, "$t ids that reference the blob")
        or diag explain $info;
    }
  };

  subtest "an unknown blob gets empty lists" => sub {
    my $id = 'nosuchblob-' . time();
    my $res = $tester->request([[
      "Blob/lookup" => { typeNames => \@types, ids => [ $id ] },
    ]]);
    ok($res->is_success, "Blob/lookup") or diag explain $res->response_payload;
    my $args = $res->single_sentence("Blob/lookup")->arguments;
    my ($info) = grep { $_->{id} eq $id } @{ $args->{list} // [] };
    if ($info) {
      # "the server MUST still return an empty array for each type"
      jcmp_deeply($info->{matchedIds}, { map { $_ => [] } @types }, "every type maps to an empty array");
    }
    else {
      # RFC 9404's own example lists it in notFound instead; accept that too.
      jcmp_deeply($args->{notFound}, [ $id ], "or the id is in notFound");
    }
  };

  subtest "an unknown type name" => sub {
    my $res = $tester->request([[
      "Blob/lookup" => { typeNames => [ 'NoSuchType' ], ids => [ $email->blobId ] },
    ]]);
    jcmp_deeply(
      $res->single_sentence->arguments,
      superhashof({ type => jstr('unknownDataType') }),
      "a type name the server does not know is an unknownDataType error",
    ) or diag explain $res->as_stripped_triples;
  };
};
