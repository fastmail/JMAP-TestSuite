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
    id                    => jstr,
    name                  => jstr,
    color                 => ignore(),
    sortOrder             => jnum,
    isVisible             => jbool,
    isDefault             => jbool,
    isSubscribed          => jbool,
    includeInAvailability => jstr,
    description           => ignore(),
    timeZone              => ignore(),
    myRights              => superhashof({
      mayReadFreeBusy  => jbool,
      mayReadItems     => jbool,
      mayWriteAll      => jbool,
      mayWriteOwn      => jbool,
      mayUpdatePrivate => jbool,
      mayRSVP          => jbool,
      mayShare         => jbool,
      mayDelete        => jbool,
    }),
  );

  # RFC 8984: defaultAlerts fields are optional (server may omit them)
  my %optional = (
    defaultAlertsWithTime    => ignore(),
    defaultAlertsWithoutTime => ignore(),
    shareWith                => ignore(),
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
