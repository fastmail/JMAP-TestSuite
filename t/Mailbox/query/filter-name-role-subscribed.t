use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $tag = "jmtsfilter$^T$$";

  my $sub   = $account->create_mailbox({ name => "a${tag}sub",   isSubscribed => JSON::true });
  my $unsub = $account->create_mailbox({ name => "b${tag}unsub", isSubscribed => JSON::false });
  my $other = $account->create_mailbox({ name => "c jmtsother$^T$$" });

  my $query = sub {
    my ($filter) = @_;
    my $res = $tester->request([[ "Mailbox/query" => { filter => $filter } ]]);
    ok($res->is_success, "Mailbox/query") or diag explain $res->response_payload;
    return $res->single_sentence("Mailbox/query")->arguments->{ids};
  };

  subtest "name" => sub {
    # RFC 8621 S2.3: 'The Mailbox "name" property contains the given string.'
    jcmp_deeply(
      $query->({ name => $tag }),
      bag($sub->id, $unsub->id),
      "a name filter matches a substring inside a word",
    );
  };

  subtest "isSubscribed" => sub {
    # RFC 8621 S2.3: isSubscribed "must be identical to the value given".
    jcmp_deeply(
      $query->({ name => $tag, isSubscribed => JSON::true }),
      [ $sub->id ],
      "isSubscribed true",
    );
    jcmp_deeply(
      $query->({ name => $tag, isSubscribed => JSON::false }),
      [ $unsub->id ],
      "isSubscribed false",
    );
  };

  subtest "role" => sub {
    my $list = $tester->request([[
      "Mailbox/get" => { properties => [ 'role' ] },
    ]])->single_sentence("Mailbox/get")->arguments->{list};
    my ($holder) = grep { defined $_->{role} } @$list;
    plan skip_all => "account has no Mailbox with a role" unless $holder;

    # RFC 8621 S2.3: role "must match the given value exactly"; S2 allows at
    # most one Mailbox per role.
    jcmp_deeply(
      $query->({ role => $holder->{role} }),
      [ $holder->{id} ],
      "role $holder->{role} matches its one holder",
    );

    my $no_role = $query->({ role => undef });
    jcmp_deeply($no_role, supersetof($sub->id, $unsub->id, $other->id),
      "role null matches Mailboxes without a role");
    jcmp_deeply($no_role, noneof($holder->{id}),
      "role null does not match a Mailbox with a role");
  };
};
