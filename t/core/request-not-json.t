use jmaptest;

# RFC 8620 S3.6.1: a request whose content type is not application/json, or
# that does not parse as I-JSON, is rejected with problem type notJSON.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities('urn:ietf:params:jmap:core');

  my $good = JSON->new->encode({
    using       => [ 'urn:ietf:params:jmap:core' ],
    methodCalls => [ [ 'Core/echo', { hello => 'world' }, 'c0' ] ],
  });

  for my $case (
    [ "a body that is not JSON",     '{"using": [', 'application/json' ],
    [ "a duplicate member name",     '{"using": [], "using": [], "methodCalls": []}', 'application/json' ],
    [ "a content type of text/plain", $good, 'text/plain' ],
  ) {
    my ($desc, $body, $type) = @$case;

    subtest $desc => sub {
      my $res = $self->raw_api_post($tester, $body, $type);
      $self->request_level_error_ok($res, 'notJSON', $desc);
    };
  }
};
