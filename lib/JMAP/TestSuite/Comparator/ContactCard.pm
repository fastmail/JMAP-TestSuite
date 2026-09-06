package JMAP::TestSuite::Comparator::ContactCard;
use Moose;

use Test::Deep ':v1';
use Test::Deep::JType;
use Test::Deep::HashRec;

use Sub::Exporter -setup => [ qw(contact_card) ];

sub contact_card {
  my ($overrides) = @_;

  $overrides ||= {};

  my %required = (
    id       => jstr,
    uid      => jstr,
    q(@type) => jstr('Card'),
    version  => jstr(),
  );

  my %optional = (
    addressBookIds => ignore(),
    name           => ignore(),
    kind           => ignore(),
    emails         => ignore(),
    phones         => ignore(),
    online         => ignore(),
    addresses      => ignore(),
    notes          => ignore(),
    anniversaries  => ignore(),
    personalInfo   => ignore(),
    keywords       => ignore(),
    media          => ignore(),
    prodId         => ignore(),
    created        => ignore(),
    updated        => ignore(),
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
