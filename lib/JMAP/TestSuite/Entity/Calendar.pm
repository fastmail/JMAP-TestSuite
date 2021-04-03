package JMAP::TestSuite::Entity::Calendar;
use Moose;
use Carp ();
with 'JMAP::TestSuite::Entity' => {
  singular_noun => 'calendar',
  properties  => [ qw(
    id
    name
    color
    sortOrder
    isVisible
    mayReadFreeBusy
    mayReadItems
    mayAddItems
    mayModifyItems
    mayRemoveItems
    mayRename
    mayDelete
  ) ],
};

no Moose;
__PACKAGE__->meta->make_immutable;
