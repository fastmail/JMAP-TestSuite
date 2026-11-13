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
  my $message = $mbox->add_message({ subject => "update and destroy $$" });
  my $id      = $message->id;

  my $res = $tester->request([[
    "Email/set" => {
      update  => { $id => { 'keywords/$seen' => jtrue } },
      destroy => [ $id ],
    },
  ]]);
  my $args = $res->single_sentence('Email/set')->arguments;

  # RFC 8620 S5.3: "The server MAY skip an update (rejecting it with a
  # "willDestroy" SetError) if that object is destroyed in the same /set
  # request."
  jcmp_deeply(
    $args,
    any(
      superhashof({ updated    => { $id => any(undef, superhashof({})) } }),
      superhashof({ notUpdated => { $id => superhashof({ type => 'willDestroy' }) } }),
    ),
    "update succeeded or was skipped with willDestroy",
  ) or diag explain $res->as_stripped_triples;

  jcmp_deeply($args->{destroyed}, [ $id ], "email was destroyed")
    or diag explain $res->as_stripped_triples;

  $tester->request_ok(
    [ "Email/get" => { ids => [ $id ], properties => [ 'id' ] } ],
    superhashof({ list => [], notFound => [ $id ] }),
    "email is gone",
  );
};
