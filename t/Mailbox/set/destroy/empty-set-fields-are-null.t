use jmaptest;

# RFC 8620 S5.3 types every /set result field "...|null": empty means null,
# never {}.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mailbox = $account->create_mailbox({ name => 'to-destroy' });

  my $res = $tester->request([[
    "Mailbox/set" => {
      destroy => [ $mailbox->id ],
    },
  ]]);

  my $args = $res->single_sentence('Mailbox/set')->arguments;

  ok($args->{destroyed}, 'destroyed is not null');
  is(scalar @{$args->{destroyed}}, 1, 'destroyed has one mailbox');

  is($args->{created}, undef, 'created is null when no creates requested');
  is($args->{notCreated}, undef, 'notCreated is null when no creates requested');
  is($args->{updated}, undef, 'updated is null when no updates requested');
  is($args->{notUpdated}, undef, 'notUpdated is null when no updates requested');
  is($args->{notDestroyed}, undef, 'notDestroyed is null when no errors');
};
