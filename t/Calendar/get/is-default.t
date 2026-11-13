use jmaptest;

# draft-ietf-jmap-calendars S4: isDefault "MUST NOT be true for more than one
# calendar within an account".

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  $account->create_calendar for 1 .. 2;

  # S4.1: "The ids argument may be null to fetch all at once."
  my $res = $tester->request([[
    "Calendar/get" => { ids => undef, properties => [qw(id isDefault)] },
  ]]);
  my $list = $res->single_sentence("Calendar/get")->arguments->{list};
  ok($list && @$list >= 2, 'got all calendars') or return diag explain $res->as_stripped_triples;

  my @defaults = grep { $_->{isDefault} } @$list;
  ok(@defaults <= 1, 'at most one calendar has isDefault true')
    or diag explain $list;
};
