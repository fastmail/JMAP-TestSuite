use jmaptest;
use JMAP::Tester::Sugar ();

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my %advertised = map {; $_ => 1 } @{ $tester->default_using // [] };
  $tester->require_capabilities('urn:ietf:params:jmap:core');

  # draft-ietf-jmap-blobext S2.1: a client "MUST NOT include both" in one
  # request, so each is tried on its own.
  my %method = (
    'urn:ietf:params:jmap:blob'  => 'Blob/upload',
    'urn:ietf:params:jmap:blob2' => 'Blob/set',
  );
  my @caps = grep {; $advertised{$_} } sort keys %method;
  plan skip_all => "server advertises neither blob capability" unless @caps;

  for my $cap (@caps) {
    my $method = $method{$cap};
    my $using  = [ 'urn:ietf:params:jmap:core', $cap ];

    my $create = sub {
      my ($data) = @_;
      my $res = $tester->request({
        using       => $using,
        methodCalls => [[ $method => { create => { b1 => { data => $data } } } ]],
      });
      ok($res->is_success, $method) or diag(explain($res->response_payload)), return {};
      my $s = $res->single_sentence;
      is($s->name, $method, "$method response, not an error")
        or diag(explain($s->as_stripped_pair)), return {};
      return $s->arguments;
    };

    subtest "$method: 64 DataSourceObjects" => sub {
      # RFC 9404 S4.1 and draft-ietf-jmap-blobext S2.1: servers "MUST" accept
      # at least 64 DataSourceObjects per creation.
      my $args = $create->([ map {; { 'data:asText' => chr(65 + $_ % 26) } } 0 .. 63 ]);
      jcmp_deeply(
        $args->{created}{b1},
        superhashof({ id => jstr, size => jnum(64) }),
        "blob of 64 parts created",
      ) or diag explain $args;
    };

    subtest "$method: invalid base64" => sub {
      # RFC 9404 S4.1: "invalid characters in the base64 of data:asBase64 ...
      # MUST result in a notCreated response".
      my $args = $create->([ { 'data:asBase64' => '!!not base64!!' } ]);
      ok(!$args->{created}{b1}, "not created") or diag explain $args;
      jcmp_deeply($args->{notCreated}{b1}, superhashof({ type => jstr }), "notCreated")
        or diag explain $args;
    };

    subtest "$method: data:asText that is not valid Unicode" => sub {
      # RFC 9404 S4.1: "invalid UTF-8 in data:asText MUST result in a
      # notCreated response". A lone surrogate also makes the request not
      # I-JSON, so RFC 8620 S3.6.1 notJSON is allowed instead.
      my $json = JSON->new->canonical->encode({
        using       => $using,
        methodCalls => [[ $method => {
          accountId => $account->accountId,
          create    => { b1 => { data => [ { 'data:asText' => 'LONE-SURROGATE' } ] } },
        }, 'c1' ]],
      });
      $json =~ s/"LONE-SURROGATE"/"\\ud800"/ or die "placeholder not found";

      my $res = $tester->request(JMAP::Tester::JSONLiteral->new($json));
      unless ($res->is_success) {
        my $http = $res->http_response;
        my $problem = eval { decode_json($http->decoded_content) } // {};
        is($problem->{type}, 'urn:ietf:params:jmap:error:notJSON', "request rejected as notJSON")
          or diag $http->as_string;
        return;
      }

      my $s = $res->single_sentence;
      is($s->name, $method, "$method response, not an error")
        or diag(explain($s->as_stripped_pair)), return;
      my $args = $s->arguments;
      ok(!$args->{created}{b1}, "not created") or diag explain $args;
      jcmp_deeply($args->{notCreated}{b1}, superhashof({ type => jstr }), "notCreated")
        or diag explain $args;
    };

    next unless $cap eq 'urn:ietf:params:jmap:blob2';

    subtest "$method: data:asText and data:asBase64 together" => sub {
      # draft-ietf-jmap-blobext S3: they "MUST NOT both be present in the same
      # DataSourceObject"; S4: an invalid one "MUST" be notCreated.
      my $args = $create->([ { 'data:asText' => 'abc', 'data:asBase64' => 'YWJj' } ]);
      ok(!$args->{created}{b1}, "not created") or diag explain $args;
      jcmp_deeply($args->{notCreated}{b1}, superhashof({ type => jstr }), "notCreated")
        or diag explain $args;
    };
  }
};
