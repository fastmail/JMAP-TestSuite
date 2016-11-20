package JMAP::TestSuite::Entity::Mailbox;
use Moose;
with 'JMAP::TestSuite::Entity' => {
  plural_noun => 'mailboxes',
  properties  => [ qw(
    id
    name
    parentId
    role
    sortOrder
    mustBeOnlyMailbox
    mayReadItems
    mayAddItems
    mayRemoveItems
    mayCreateChild
    mayRename
    mayDelete
    totalMessages
    unreadMessages
    totalThreads
    unreadThreads
  ) ],
};

no Moose;
__PACKAGE__->meta->make_immutable;
