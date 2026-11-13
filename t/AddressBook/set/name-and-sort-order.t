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

  my $set = sub {
    my ($props) = @_;
    my $res = $tester->request([[
      "AddressBook/set" => {
        create => { new => { name => "Limits " . guid_string(), %$props } },
        update => { $ab->id => $props },
      },
    ]]);
    ok($res->is_success, "AddressBook/set") or diag explain $res->response_payload;
    return $res->single_sentence("AddressBook/set")->arguments;
  };

  # RFC 9610 S2: name "MUST NOT be the empty string and MUST NOT be greater
  # than 255 octets in size when encoded as UTF-8"; sortOrder "MUST be an
  # integer in the range 0 <= sortOrder < 2^31".
  my %bad = (
    'empty name'                       => [ name => '' ],
    'name of 256 ASCII octets'         => [ name => 'a' x 256 ],
    'name of 128 two-octet characters' => [ name => "\x{e9}" x 128 ],
    'negative sortOrder'               => [ sortOrder => -1 ],
    'sortOrder of 2^31'                => [ sortOrder => 2**31 ],
  );

  for my $what (sort keys %bad) {
    my ($prop, $value) = @{ $bad{$what} };
    subtest $what => sub {
      my $args = $set->({ $prop => $value });
      ok(!$args->{created}{new}, "not created") or diag explain $args;
      jcmp_deeply($args->{notCreated}{new}, invalid_properties($prop), "create is invalidProperties")
        or diag explain $args;
      ok(!exists(($args->{updated} // {})->{ $ab->id }), "not updated") or diag explain $args;
      jcmp_deeply($args->{notUpdated}{ $ab->id }, invalid_properties($prop), "update is invalidProperties")
        or diag explain $args;
    };
  }

  my %good = (
    'name of 255 octets'  => [ name => ("\x{e9}" x 127) . 'a' ],
    'sortOrder of 2^31-1' => [ sortOrder => 2**31 - 1 ],
  );

  for my $what (sort keys %good) {
    my ($prop, $value) = @{ $good{$what} };
    subtest $what => sub {
      my $args = $set->({ $prop => $value });
      ok($args->{created}{new}, "created") or diag explain $args;
      ok(exists(($args->{updated} // {})->{ $ab->id }), "updated") or diag explain $args;
    };
  }
};
