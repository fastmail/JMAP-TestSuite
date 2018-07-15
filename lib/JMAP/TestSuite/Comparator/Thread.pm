package JMAP::TestSuite::Comparator::Thread;
use Moose;

use Test::Deep ':v1';
use Test::Deep::JType;
use Test::Deep::HashRec;

use Sub::Exporter -setup => [ qw(thread) ];

sub thread {
  my ($overrides) = @_;

  $overrides ||= {};

  my %required = (
    id            => jstr,
    emailIds      => any([], array_each(jstr)),
  );

  my %optional = ();

  for my $k (keys %$overrides) {
    if (exists $required{$k}) {
      $required{$k} = $overrides->{$k};
    } else {
      $optional{$k} = $overrides->{$k};
    }
  }

  return hashrec({
    required => \%required,
    optional => \%optional,
  });
}

no Moose;
__PACKAGE__->meta->make_immutable;
