use jmaptest;

attr pristine  => 1;
attr pool_pairs => 1;

test {
  my ($self) = @_;

  my ($from_account, $to_account) = $self->pool_account_pair;
  my $from_tester = $from_account->tester;

  $from_tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $src_mbox  = $from_account->create_mailbox;
  my $dest_mbox = $to_account->create_mailbox;
  my $msg = $src_mbox->add_message({ subject => "copy settable $$" });

  # RFC 8621 S4.7: "only the "mailboxIds", "keywords", and "receivedAt"
  # properties may be set during the copy."
  for my $case (
    [ subject         => "changed $$" ],
    [ from            => [ { name => 'Changed', email => 'changed@example.com' } ] ],
    [ 'header:X-Foo'  => ' bar' ],
    [ bodyStructure   => { type => 'text/plain', partId => 'body' } ],
  ) {
    my ($prop, $value) = @$case;

    subtest "setting $prop" => sub {
      my $res = $from_tester->request([[
        "Email/copy" => {
          fromAccountId => $from_account->accountId,
          accountId     => $to_account->accountId,
          create => {
            c1 => {
              id         => $msg->id,
              mailboxIds => { $dest_mbox->id => jtrue },
              $prop      => $value,
            },
          },
        },
      ]]);

      my $args = $res->single_sentence('Email/copy')->arguments;
      jcmp_deeply(
        $args->{notCreated},
        { c1 => invalid_properties($prop) },
        "copy is rejected",
      ) or diag explain $res->as_stripped_triples;

      if (my $created = $args->{created}{c1}) {
        $to_account->tester->request([[ "Email/set" => { destroy => [ $created->{id} ] } ]]);
      }
    };
  }
};
