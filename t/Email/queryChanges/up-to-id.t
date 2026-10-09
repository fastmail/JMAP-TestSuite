use jmaptest;

use DateTime;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  # receivedAt is immutable, so a window on it lets upToId take effect.
  # The window is far in the future and keyed on our pid, so the shared
  # account holds no other email in it.
  my $start = DateTime->new(year => 2061, time_zone => 'UTC')
                      ->add(minutes => ($$ % 100_000) * 2);
  my $at = sub { $start->clone->add(seconds => $_[0])->strftime('%FT%TZ') };

  my $mailbox = $account->create_mailbox;
  my %email = map {;
    $_ => $mailbox->add_message({ subject => "upToId $_ $$", receivedAt => $at->($_) })
  } (10, 20, 30);

  my %args = (
    filter => { after => $at->(0), before => $at->(100) },
    sort   => [ { property => 'receivedAt', isAscending => jtrue() } ],
  );

  my $query = sub {
    my $res = $tester->request([[ "Email/query" => \%args ]]);
    ok($res->is_success, "Email/query") or diag explain $res->response_payload;
    return $res->single_sentence("Email/query")->arguments;
  };

  my $old = $query->();
  is_deeply(
    [ map {; "$_" } @{ $old->{ids} } ],
    [ map {; $email{$_}->id } (10, 20, 30) ],
    "the window holds our three emails",
  ) or return diag explain $old;

  unless ($old->{canCalculateChanges}) {
    note("server cannot calculate changes for this query (RFC 8620 S5.5)");
    return;
  }

  $email{$_} = $mailbox->add_message({ subject => "upToId $_ $$", receivedAt => $at->($_) })
    for (15, 40);

  my $new = $query->();

  my $res = $tester->request([[
    "Email/queryChanges" => {
      %args,
      sinceQueryState => $old->{queryState},
      upToId          => $email{20}->id,
    },
  ]]);
  ok($res->is_success, "Email/queryChanges")
    or return diag explain $res->response_payload;

  my ($name, $changes) = @{ $res->sentence(0)->as_stripped_pair };
  is($name, 'Email/queryChanges', 'got Email/queryChanges')
    or return diag explain $changes;

  # RFC 8620 S5.6: only changes past upToId "SHOULD be omitted", so applying
  # the changes must still give the new results up to and including upToId.
  my %removed = map {; $_ => 1 } @{ $changes->{removed} || [] };
  my @ids = grep {; ! $removed{$_} } map {; "$_" } @{ $old->{ids} };
  for my $item (sort { $a->{index} <=> $b->{index} } @{ $changes->{added} || [] }) {
    splice @ids, $item->{index}, 0, "$item->{id}";
  }

  my @want = map {; $email{$_}->id } (10, 15, 20);
  is_deeply([ @ids[0 .. 2] ], \@want, "the results up to upToId are correct")
    or diag explain [ $old, $changes, $new ];

  note(
    (grep {; $_->{id} eq $email{40}->id } @{ $changes->{added} || [] })
      ? "the addition after upToId was reported (RFC 8620 S5.6 says it SHOULD be omitted)"
      : "the addition after upToId was omitted"
  );
};
