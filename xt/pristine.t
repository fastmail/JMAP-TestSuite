use jmaptest;

attr pristine => 1;

test {
  my ($self) = @_;

  my $account_1 = $self->any_account;
  my $account_2 = $self->pristine_account;

  # Cheat - just make sure we don't get a reused account
  isnt(
    $account_1->accountId,
    $account_2->accountId,
    'Got unique accountIds from pristine_account',
  );
};
