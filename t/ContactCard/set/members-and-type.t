use jmaptest;
use Data::GUID qw(guid_string);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:contacts',
  );

  my $ab = $account->create_address_book;
  my $member_uid = "urn:uuid:" . lc guid_string();

  my $set = sub {
    my ($arg) = @_;
    my $res = $tester->request([[ "ContactCard/set" => $arg ]]);
    ok($res->is_success, "ContactCard/set") or diag explain $res->response_payload;
    return $res->single_sentence("ContactCard/set")->arguments;
  };

  my $card = sub {
    return {
      '@type'        => 'Card',
      version        => '1.0',
      uid            => "urn:uuid:" . lc guid_string(),
      name           => { full => "Members Test" },
      addressBookIds => { $ab->id => \1 },
      @_,
    };
  };

  # RFC 9553 S2.1.6: if members "is set, then the value of the kind property
  # MUST be 'group'"; kind defaults to "individual" (S2.1.4).
  my %bad = (
    'members without kind'  => [ members => { $member_uid => \1 } ],
    'members with kind org' => [ members => { $member_uid => \1 }, kind => 'org' ],
    # RFC 9553 S2.1.1: the Card @type "MUST be 'Card'".
    '@type other than Card' => [ '@type' => 'Group' ],
  );

  for my $what (sort keys %bad) {
    subtest $what => sub {
      my $args = $set->({ create => { c1 => $card->(@{ $bad{$what} }) } });
      ok(!$args->{created}{c1}, "not created") or diag explain $args;
      jcmp_deeply($args->{notCreated}{c1}, invalid_properties(), "invalidProperties")
        or diag explain $args;
    };
  }

  subtest "a group card may have members" => sub {
    my $args = $set->({
      create => { c1 => $card->(kind => 'group', members => { $member_uid => \1 }) },
    });
    my $id = $args->{created}{c1}{id};
    ok($id, "group card created") or diag(explain($args)), return;

    $args = $set->({ update => { $id => { kind => 'individual' } } });
    ok(!exists(($args->{updated} // {})->{$id}), "kind cannot change away from group while members is set")
      or diag explain $args;
    jcmp_deeply($args->{notUpdated}{$id}, invalid_properties(), "invalidProperties")
      or diag explain $args;
  };
};
