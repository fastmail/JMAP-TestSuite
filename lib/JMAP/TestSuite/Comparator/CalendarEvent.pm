package JMAP::TestSuite::Comparator::CalendarEvent;
use Moose;

use Test::Deep ':v1';
use Test::Deep::JType;
use Test::Deep::HashRec;

use Sub::Exporter -setup => [ qw(calendar_event jduration) ];

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
    # draft-ietf-jmap-calendars section 5.1 additions
    mayInviteSelf            => ignore(),
    mayInviteOthers          => ignore(),
    hideAttendees            => ignore(),
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

  # jscalendarbis S1.7.4: implementations "MUST preserve" unknown properties.
  return hashrec({
    required => \%required,
    optional => \%optional,
    allow_unknown => 1,
  });
}

# jscalendarbis S1.5.6 Duration ABNF.
my $DUR_TIME = qr/T(?:\d+H(?:\d+M(?:\d+S)?)?|\d+M(?:\d+S)?|\d+S)/;
my $DUR_CAL  = qr/(?:\d+W(?:\d+D)?|\d+D)/;
my $DURATION = qr/\AP(?:$DUR_CAL$DUR_TIME?|$DUR_TIME)\z/;

sub _duration_parts {
  my ($str) = @_;
  return unless defined $str && !ref $str && $str =~ $DURATION;
  my %n = map {; $_ => 0 } qw(W D H M S);
  my ($cal, $time) = $str =~ /\AP([^T]*)(.*)\z/;
  $n{$2} = $1 while $cal  =~ /(\d+)([WD])/g;
  $n{$2} = $1 while $time =~ /(\d+)([HMS])/g;
  # S1.5.6: a week is always seven days, but a day is not always 24 hours.
  return [ $n{W} * 7 + $n{D}, $n{H} * 3600 + $n{M} * 60 + $n{S} ];
}

=head2 jduration

  duration => jduration('PT2H'),

Matches any JSCalendar Duration string denoting the same length of time,
so PT2H also matches PT120M and PT7200S, but not P1D or PT2H0M0.5S.

=cut

sub jduration {
  my ($want) = @_;
  my $w = _duration_parts($want) or die "jduration: bad Duration '$want'";

  return all(jstr, code(sub {
    my $got = "$_[0]";
    my $g = _duration_parts($got)
      or return (0, "'$got' is not a JSCalendar Duration");
    return 1 if $g->[0] == $w->[0] && $g->[1] == $w->[1];
    return (0, "'$got' is not equivalent to '$want'");
  }));
}

no Moose;
__PACKAGE__->meta->make_immutable;
