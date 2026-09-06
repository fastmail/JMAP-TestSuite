package JMAP::TestSuite::Comparator::CalendarEvent;
use Moose;

use Test::Deep ':v1';
use Test::Deep::JType;
use Test::Deep::HashRec;

use Sub::Exporter -setup => [ qw(calendar_event) ];

sub calendar_event {
  my ($overrides) = @_;

  $overrides ||= {};

  my %required = (
    id          => jstr,
    calendarIds => ignore(),
    title       => ignore(),
    start       => jstr,
    timeZone    => ignore(),
    isOrigin    => jbool,
    isDraft     => jbool,
  );

  my %optional = (
    # jscalendarbis fields
    uid                      => ignore(),
    version                  => ignore(),
    duration                 => ignore(),
    endTimeZone              => ignore(),
    recurrenceRule           => ignore(),
    recurrenceId             => ignore(),
    recurrenceIdTimeZone     => ignore(),
    recurrenceOverrides      => ignore(),
    showWithoutTime          => ignore(),
    locations                => ignore(),
    participants             => ignore(),
    status                   => ignore(),
    privacy                  => ignore(),
    organizerCalendarAddress => ignore(),
    freeBusyStatus           => ignore(),
    alerts                   => ignore(),
    sequence                 => ignore(),
    created                  => ignore(),
    updated                  => ignore(),
    description              => ignore(),
    keywords                 => ignore(),
    color                    => ignore(),
    relatedTo                => ignore(),
    priority                 => ignore(),
    descriptionContentType   => ignore(),
    locale                   => ignore(),
    links                    => ignore(),
    virtualLocations         => ignore(),
    baseEventId              => ignore(),
    # per-user properties (jmap-calendars)
    useDefaultAlerts         => ignore(),
    # iCalendar/CalDAVTalk passthrough fields
    q(@type)                 => ignore(),
    prodId                   => ignore(),
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
