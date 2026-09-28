package JMAP::TestSuite::Entity::ContactCard;
use Moose;
use Carp ();
with 'JMAP::TestSuite::Entity' => {
  singular_noun => 'contactCard',
  properties  => [ qw(
    id
    uid
    addressBookIds
    name
    emails
    phones
    online
    addresses
    notes
    anniversaries
    personalInfo
    keywords
    media
  ) ],
};

no Moose;
__PACKAGE__->meta->make_immutable;
