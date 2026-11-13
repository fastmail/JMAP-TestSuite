use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mbox    = $account->create_mailbox;
  my $subject = "immutable $$";
  my $message = $mbox->add_message({
    subject    => $subject,
    receivedAt => '2020-01-02T03:04:05Z',
  });
  my $id = $message->id;

  my @props = qw(blobId threadId subject from receivedAt);
  my $get_res = $tester->request([[
    "Email/get" => { ids => [ $id ], properties => \@props },
  ]]);
  my $orig = $get_res->single_sentence('Email/get')->arguments->{list}[0];
  ok($orig, "got the email") or return diag explain $get_res->as_stripped_triples;

  # RFC 8621 S4.1 marks these immutable, so "The value MUST NOT change after
  # the object is created" (RFC 8620 S1.1).
  for my $case (
    [ subject    => "changed $$" ],
    [ from       => [ { name => 'Changed', email => 'changed@example.com' } ] ],
    [ receivedAt => '2021-01-02T03:04:05Z' ],
    [ bodyStructure => { type => 'text/plain', partId => 'body' } ],
    [ blobId     => 'not-the-blob-id' ],
  ) {
    my ($prop, $value) = @$case;

    subtest "changing $prop" => sub {
      my $patch = { $prop => $value };
      $patch->{bodyValues} = { body => { value => "changed" } }
        if $prop eq 'bodyStructure';

      my $res = $tester->request([[
        "Email/set" => { update => { $id => $patch } },
      ]]);
      jcmp_deeply(
        $res->single_sentence('Email/set')->arguments->{notUpdated},
        { $id => invalid_properties($prop) },
        "update is rejected",
      ) or diag explain $res->as_stripped_triples;

      $tester->request_ok(
        [ "Email/get" => { ids => [ $id ], properties => \@props } ],
        superhashof({ list => [ $orig ] }),
        "email is unchanged",
      );
    };
  }

  # RFC 8620 S5.3: "Any server-set properties MAY be included in the patch if
  # their value is identical to the current server value".
  for my $prop (qw(blobId threadId)) {
    subtest "$prop with its current value" => sub {
      my $res = $tester->request([[
        "Email/set" => {
          update => { $id => { $prop => $orig->{$prop}, 'keywords/$seen' => jtrue } },
        },
      ]]);
      jcmp_deeply(
        $res->single_sentence('Email/set')->arguments->{updated},
        { $id => any(undef, superhashof({})) },
        "update is accepted",
      ) or diag explain $res->as_stripped_triples;
    };
  }
};
