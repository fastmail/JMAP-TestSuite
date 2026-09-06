package JMAP::TestSuite::Entity::AddressBook;
use Moose;
use Carp ();
with 'JMAP::TestSuite::Entity' => {
  singular_noun => 'addressBook',
  properties  => [ qw(
    id
    name
    isDefault
    isSubscribed
    myRights
  ) ],
};

no Moose;
__PACKAGE__->meta->make_immutable;
