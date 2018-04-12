package JMAP::TestSuite::Entity::Mailbox;
use Moose;
use Carp ();
with 'JMAP::TestSuite::Entity' => {
  singular_noun => 'mailbox',
  properties  => [ qw(
    id
    name
    parentId
    role
    sortOrder
    mustBeOnlyMailbox
    myRights
    totalEmails
    unreadEmails
    totalThreads
    unreadThreads
  ) ],
};

for my $f (qw(
  mayReadItems
  mayAddItems
  mayRemoveItems
  maySetSeen
  maySetKeywords
  mayCreateChild
  mayRename
  mayDelete
  maySubmit
)) {
  no strict 'refs';

  *{$f} = sub {
    Carp::croak("Cannot assign a value to a read-only accessor") if @_ > 1;
    return $_[0]->_props->{myRights}{$f};
  };
}

no Moose;
__PACKAGE__->meta->make_immutable;
