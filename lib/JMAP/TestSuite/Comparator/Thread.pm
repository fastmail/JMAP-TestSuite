package JMAP::TestSuite::Comparator::Thread;
use Moose;

use Test::Deep ':v1';
use Test::Deep::JType;

use Sub::Exporter -setup => [ qw(thread) ];

sub thread {
  my ($req_override, $opt_override) = @_;

  $req_override ||= {};
  $opt_override ||= {};

  my %required = (
    id            => jstr,
    emailIds      => any([], array_each(jstr)),
  );

  my %optional = ();

  # superhashof ensures all of the keys exist and match
  # subhashof ensures that the provided keys are only ones we expect
  # (and their values match too)
  # This way we can say "this set of things is required" and "this
  # set of things is optional" since the server may omit things with
  # default values
  return all(
    superhashof(\%required),
    subhashof({ %required, %optional })
  );
}

no Moose;
__PACKAGE__->meta->make_immutable;
