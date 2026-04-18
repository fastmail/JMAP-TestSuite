package JMAP::TestSuite::Comparator::Calendar;
use Moose;

use Test::Deep ':v1';
use Test::Deep::JType;
use Test::Deep::HashRec;

use Sub::Exporter -setup => [ qw(calendar) ];

sub calendar {
  my ($overrides) = @_;

  $overrides ||= {};

  my %required = (
    id              => jstr,
    name            => jstr,
    color           => jstr,
    sortOrder       => jnum,
    isVisible       => jbool,
    mayReadFreeBusy => jbool,
    mayReadItems    => jbool,
    mayAddItems     => jbool,
    mayModifyItems  => jbool,
    mayRemoveItems  => jbool,
    mayRename       => jbool,
    mayDelete       => jbool,
  );

  my %optional;

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
