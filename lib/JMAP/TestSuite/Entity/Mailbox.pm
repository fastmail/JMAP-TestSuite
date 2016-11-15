package JMAP::TestSuite::Entity::Mailbox;
use Moose;
with 'JMAP::TestSuite::Entity' => {
  plural_noun => 'mailboxes',
  properties  => [ qw(id name parentId role) ], # TODO: flesh out
};

no Moose;
__PACKAGE__->meta->make_immutable;
