use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:contacts',
  );

  my $session = fetch_session($tester) or return;
  $session = JSON::Typist->new->apply_types($session);

  # RFC 9610 S1.4.1: the session-level value "is an empty object".
  jcmp_deeply(
    $session->{capabilities}{'urn:ietf:params:jmap:contacts'},
    {},
    "session capability is an empty object",
  ) or diag explain $session->{capabilities};

  my $cap = $session->{accounts}{ $account->accountId }{accountCapabilities}
                    {'urn:ietf:params:jmap:contacts'};
  ok($cap, "account has a contacts accountCapability") or return;

  # RFC 9610 S1.4.1: it "MUST contain" both; maxAddressBooksPerCard "MUST be
  # an integer >= 1, or null".
  jcmp_deeply(
    $cap,
    superhashof({
      maxAddressBooksPerCard => any(
        undef,
        all(jnum, code(sub { $_[0] == int $_[0] && $_[0] >= 1 })),
      ),
      mayCreateAddressBook   => jbool,
    }),
    "account capability has maxAddressBooksPerCard and mayCreateAddressBook",
  ) or diag explain $cap;
};
