package JMAP::TestSuite::Entity::CalendarEvent;
use Moose;
use Carp ();
with 'JMAP::TestSuite::Entity' => {
  singular_noun => 'calendarEvent',
  properties  => [ qw(
    id
    uid
    calendarIds
    title
    start
    duration
    timeZone
    isOrigin
    recurrenceRule
    recurrenceId
    recurrenceIdTimeZone
    recurrenceOverrides
    showWithoutTime
    locations
    participants
    status
    privacy
    organizerCalendarAddress
    freeBusyStatus
    alerts
    sequence
    created
    updated
    description
    keywords
    color
  ) ],
};

no Moose;
__PACKAGE__->meta->make_immutable;
