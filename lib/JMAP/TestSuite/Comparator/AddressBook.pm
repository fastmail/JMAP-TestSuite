package JMAP::TestSuite::Comparator::AddressBook;
use Moose;

use Test::Deep ':v1';
use Test::Deep::JType;
use Test::Deep::HashRec;

use Sub::Exporter -setup => [ qw(address_book) ];

sub address_book {
  my ($overrides) = @_;

  $overrides ||= {};

  my %required = (
    id          => jstr,
    name        => jstr,
    isDefault   => jbool,
    isSubscribed => jbool,
    myRights    => superhashof({
      mayRead   => jbool,
      mayWrite  => jbool,
      mayShare  => jbool,
      mayDelete => jbool,
    }),
  );

  my %optional = (
    description => ignore(),
    sortOrder   => ignore(),
    shareWith   => ignore(),
  );

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
