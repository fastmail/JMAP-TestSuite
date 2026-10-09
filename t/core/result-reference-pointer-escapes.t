use jmaptest;

# RFC 8620 S3.7: a ResultReference path is a JSON Pointer (RFC 6901), so "~1"
# in a token stands for "/" and "~0" for "~".

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $target = $account->create_mailbox;
  my $decoy  = $account->create_mailbox;

  # RFC 8620 S4: Core/echo returns its arguments unchanged, giving keys with
  # "/" and "~" in them; the decoys catch a server that skips unescaping.
  my %echo = (
    accountId => \undef,
    "plain"   => [ $target->id ],
    "a/b~c"   => [ $target->id ],
    "a~1b~0c" => [ $decoy->id ],
    "a"       => { "b~c" => [ $decoy->id ], "b" => { "~c" => [ $decoy->id ] } },
  );

  for my $case (
    [ "/plain",    "a pointer into a Core/echo response resolves" ],
    [ "/a~1b~0c",  '"/a~1b~0c" selects the key "a/b~c"' ],
  ) {
    my ($path, $desc) = @$case;

    subtest $desc => sub {
      my $res = $tester->request([
        [ "Core/echo" => \%echo, "t0" ],
        [ "Mailbox/get" => {
            "#ids" => { resultOf => "t0", name => "Core/echo", path => $path },
            properties => [ "name" ],
          }, "t1" ],
      ]);
      ok($res->is_success, "the request completed")
        or return diag explain $res->response_payload;

      is($res->sentence(0)->name, "Core/echo", "Core/echo answered")
        or return diag explain $res->as_stripped_triples;

      is($res->sentence(1)->name, "Mailbox/get", "the reference resolved")
        or return diag explain $res->as_stripped_triples;

      jcmp_deeply(
        $res->sentence(1)->arguments->{list},
        [ { id => jstr($target->id), name => jstr($target->name) } ],
        "it resolved to the right ids",
      ) or diag explain $res->as_stripped_triples;
    };
  }
};
