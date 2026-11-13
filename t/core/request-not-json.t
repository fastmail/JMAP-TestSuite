use jmaptest;

# RFC 8620 S3.6.1: problem type notJSON means "The content type of the request
# was not application/json or the request did not parse as I-JSON".
#
# A body that is not JSON at all cannot be processed, so it must be rejected.
#
# The I-JSON and application/json requirements, though, are on the client:
# S1.5 says data sent "MUST be valid I-JSON" and S3.1 says "The request MUST be
# of type application/json".  Nothing requires the server to reject a request
# that breaks them: RFC 7493 S3 lets a protocol require receivers to reject
# non-I-JSON messages, and RFC 8620 does not, beyond the MAY of notJSON.
# So for a duplicate member name and a text/plain content type, the server may
# either answer notJSON or process the request normally (HTTP 200 with
# methodResponses).

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities('urn:ietf:params:jmap:core');

  my $good = JSON->new->encode({
    using       => [ 'urn:ietf:params:jmap:core' ],
    methodCalls => [ [ 'Core/echo', { hello => 'world' }, 'c0' ] ],
  });

  subtest "a body that is not JSON" => sub {
    my $desc = "a body that is not JSON";
    my $res = $self->raw_api_post($tester, '{"using": [', 'application/json');
    $self->request_level_error_ok($res, 'notJSON', $desc);
  };

  for my $case (
    [ "a duplicate member name",     '{"using": [], "using": [], "methodCalls": []}', 'application/json' ],
    [ "a content type of text/plain", $good, 'text/plain' ],
  ) {
    my ($desc, $body, $type) = @$case;

    subtest $desc => sub {
      my $res = $self->raw_api_post($tester, $body, $type);

      if ($res->is_success) {
        my $data = eval { JSON->new->decode($res->decoded_content) };
        ok(
          ref $data eq 'HASH' && ref $data->{methodResponses} eq 'ARRAY',
          "$desc: processed normally, a Response with methodResponses",
        ) or diag($res->as_string);
      } else {
        $self->request_level_error_ok($res, 'notJSON', $desc);
      }
    };
  }
};
