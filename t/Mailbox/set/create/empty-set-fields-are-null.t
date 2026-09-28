use jmaptest;

attr pristine => 1;

# RFC 8620 S5.3 types every /set result field "...|null": empty means null,
# never {}.

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $res = $tester->request([[
    "Mailbox/set" => {
      create => {
        new => {
          name => 'null fields test mailbox',
        },
      },
    },
  ]]);

  my $args = $res->single_sentence('Mailbox/set')->arguments;

  ok($args->{created}{new}, 'created has our mailbox');
  ok($args->{created}{new}{id}, 'created mailbox has id');

  is($args->{notCreated}, undef, 'notCreated is null when no errors');
  is($args->{updated}, undef, 'updated is null when no updates requested');
  is($args->{notUpdated}, undef, 'notUpdated is null when no updates requested');
  is($args->{destroyed}, undef, 'destroyed is null when no destroys requested');
  is($args->{notDestroyed}, undef, 'notDestroyed is null when no destroys requested');
};
