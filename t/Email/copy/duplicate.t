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
  my $msg = $src_mbox->add_message({ subject => "copy duplicate $$" });

  my $copy = sub {
    my $res = $from_tester->request([[
      "Email/copy" => {
        fromAccountId => $from_account->accountId,
        accountId     => $to_account->accountId,
        create => {
          c1 => { id => $msg->id, mailboxIds => { $dest_mbox->id => jtrue } },
        },
      },
    ]]);
    return $res->single_sentence('Email/copy')->arguments;
  };

  my $first = $copy->();
  my $first_id = $first->{created}{c1}{id};
  ok($first_id, "first copy succeeded") or return diag explain $first;

  my $second = $copy->();

  # RFC 8621 S4.7: a server forbidding duplicates rejects the copy "with a
  # standard "alreadyExists" error", which RFC 8620 S5.4 says MUST carry
  # "existingId"; otherwise the copy is a new Email with its own id.
  if (my $err = $second->{notCreated}{c1}) {
    jcmp_deeply(
      $err,
      superhashof({ type => 'alreadyExists', existingId => $first_id }),
      "duplicate is rejected with alreadyExists naming the existing email",
    ) or diag explain $second;
    return;
  }

  my $second_id = $second->{created}{c1}{id};
  ok($second_id, "duplicate was copied") or return diag explain $second;
  isnt($second_id, $first_id, "duplicate has a separate id");
};
