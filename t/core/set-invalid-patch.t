use jmaptest;

# RFC 8620 S5.3: a PatchObject pointer MUST NOT reference inside an array,
# all parts before the last MUST already exist, and no pointer may be a prefix
# of another; "if there is any violation, the update MUST be rejected with an
# invalidPatch error".

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $submission = 'urn:ietf:params:jmap:submission';
  my $has_identity = grep {; $_ eq $submission } @{ $tester->default_using // [] };

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
    ($has_identity ? $submission : ()),
  );

  my $mailbox = $account->create_mailbox;
  my $email   = $mailbox->add_message;

  my $rejected = sub {
    my ($method, $id, $patch) = @_;

    my $res = $tester->request([[ $method => { update => { $id => $patch } } ]]);
    ok($res->is_success, "$method completed")
      or return diag explain $res->response_payload;

    my $args = $res->single_sentence($method)->arguments;
    ok(!exists $args->{updated}{$id}, "the update was not applied")
      or diag explain $args;
    jcmp_deeply(
      $args->{notUpdated}{$id},
      superhashof({ type => "invalidPatch" }),
      "it is rejected with invalidPatch",
    ) or diag explain $args;
  };

  subtest "one pointer is a prefix of another" => sub {
    $rejected->("Email/set", $email->id, {
      keywords         => { '$flagged' => jtrue },
      'keywords/$seen' => jtrue,
    });
  };

  subtest "a parent that does not exist" => sub {
    $rejected->("Email/set", $email->id, { 'keywords/$jmtsabsent/x' => jtrue });
  };

  subtest "a pointer into an array" => sub {
    plan skip_all => "no $submission for an Identity" unless $has_identity;

    my $get = $tester->request([[ "Identity/get" => { properties => [ "email" ] } ]]);
    my ($existing) = @{ $get->single_sentence("Identity/get")->arguments->{list} // [] };
    plan skip_all => "account has no identity to copy an address from"
      unless $existing;

    my $res = $tester->request([[
      "Identity/set" => {
        create => {
          new => {
            email => $existing->{email},
            name  => "invalidPatch $^T.$$",
            bcc   => [ { name => undef, email => $existing->{email} } ],
          },
        },
      },
    ]]);
    my $id = eval { $res->single_sentence("Identity/set")->arguments->{created}{new}{id} };
    plan skip_all => "server would not create an Identity to patch"
      unless defined $id;

    $rejected->("Identity/set", $id, { 'bcc/0/email' => 'jmts@example.com' });

    $tester->request([[ "Identity/set" => { destroy => [ $id ] } ]]);
  };
};
