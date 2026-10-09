use jmaptest;

# RFC 9425 S4.1: the server "MUST filter out any types for which the client
# did not request the associated capability" and "MUST NOT return Quota
# objects for which there are no types recognized by the client".
attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;
  my $tester  = $account->tester;

  my %advertised = map {; $_ => 1 } @{ $tester->default_using // [] };
  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:quota',
  );

  # Type names from the IANA "JMAP Data Types" registry, by capability.
  my %types_for = (
    'urn:ietf:params:jmap:mail'             => [ qw(Email Mailbox Thread SearchSnippet) ],
    'urn:ietf:params:jmap:submission'       => [ qw(EmailSubmission Identity) ],
    'urn:ietf:params:jmap:vacationresponse' => [ qw(VacationResponse) ],
    'urn:ietf:params:jmap:contacts'         => [ qw(AddressBook ContactCard) ],
    'urn:ietf:params:jmap:calendars'        => [ qw(Calendar CalendarEvent CalendarEventNotification ParticipantIdentity) ],
    'urn:ietf:params:jmap:sieve'            => [ qw(SieveScript) ],
    'urn:ietf:params:jmap:filenode'         => [ qw(FileNode) ],
  );

  my $all = $tester->request({
    using       => [ sort keys %advertised ],
    methodCalls => [[ "Quota/get" => { ids => undef } ]],
  });
  ok($all->is_success, "Quota/get with every capability") or diag explain $all->response_payload;
  unless (@{ $all->single_sentence("Quota/get")->arguments->{list} }) {
    pass("server reports no quotas for this account; nothing further to check");
    return;
  }

  for my $extra (undef, grep {; $advertised{$_} } sort keys %types_for) {
    my @using = ('urn:ietf:params:jmap:core', 'urn:ietf:params:jmap:quota', $extra // ());
    my %allowed = map {; $_ => 1 } map {; @{ $types_for{$_} // [] } } @using;
    my %hidden  = map {; $_ => 1 } grep {; !$allowed{$_} } map {; @$_ } values %types_for;

    subtest "using @using[1 .. $#using]" => sub {
      my $res = $tester->request({
        using       => \@using,
        methodCalls => [[ "Quota/get" => { ids => undef } ]],
      });
      ok($res->is_success, "Quota/get") or diag(explain($res->response_payload)), return;

      for my $q (@{ $res->single_sentence("Quota/get")->arguments->{list} }) {
        my @types = @{ $q->{types} // [] };
        ok(@types, "quota $q->{id} has at least one type") or diag explain $q;
        my @bad = grep {; $hidden{$_} } @types;
        ok(!@bad, "quota $q->{id} lists no type whose capability was not used")
          or diag explain \@bad;
      }
    };
  }
};
