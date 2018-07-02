package JMAP::TestSuite::JMAP::Tester::Wrapper;
use strict;
use warnings;

use Params::Util qw(_ARRAY0);

use Moo;

extends 'JMAP::Tester';

has default_using => (
  is  => 'rw',
  isa => sub {
    die "must be an arrayref" unless _ARRAY0 $_[0];
  },
  default => sub {
    [ "ietf:jmapmail" ],
#    [ "urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
  },
);

around request => sub {
  my ($orig, $self, $input_request) = @_;

  my $request;

  if (_ARRAY0($input_request)) {
    $request = {
      methodCalls => $input_request,
    },
  } else {
    $request = $input_request;
  }

  unless (
       exists $request->{using}
    || delete $request->{no_using}
  ) {
    $request->{using} = $self->default_using;
  }

  return $orig->($self, $request);
};

1;
