use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  # Add a calendar to make sure we don't get it
  $account->create_calendar;

  my $res = $tester->request_ok(
    [ "Calendar/get" => { ids => [] } ],
    superhashof({
      accountId => jstr($account->accountId),
      state     => jstr(),
      list      => [],
    }),
    "Response for ids => [] looks good"
  );
};
