use jmaptest;

# RFC 8620 S3.6.1: a request that "parsed as JSON but did not match the type
# signature of the Request object" is rejected with problem type notRequest.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities('urn:ietf:params:jmap:core');

  my $call = [ 'Core/echo', { hello => 'world' }, 'c0' ];

  for my $case (
    [ "an array, not an object",   [ $call ] ],
    [ "no methodCalls",            { using => [ 'urn:ietf:params:jmap:core' ] } ],
    [ "using is not an array",     { using => 'urn:ietf:params:jmap:core', methodCalls => [ $call ] } ],
    [ "an Invocation of two items", { using => [ 'urn:ietf:params:jmap:core' ], methodCalls => [ [ 'Core/echo', {} ] ] } ],
  ) {
    my ($desc, $request) = @$case;

    subtest $desc => sub {
      my $res = $self->raw_api_post($tester, JSON->new->encode($request));
      $self->request_level_error_ok($res, 'notRequest', $desc);
    };
  }
};
