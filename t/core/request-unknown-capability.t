use jmaptest;

# RFC 8620 S3.6.1: a "using" capability the server does not support rejects
# the whole request; the problem type is unknownCapability.

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities('urn:ietf:params:jmap:core');

  my $res = $self->raw_api_post($tester, JSON->new->encode({
    using       => [ 'urn:ietf:params:jmap:core', 'https://jmts.example.com/no-such-capability' ],
    methodCalls => [ [ 'Core/echo', { hello => 'world' }, 'c0' ] ],
  }));

  $self->request_level_error_ok($res, 'unknownCapability', 'an unknown capability');
};
