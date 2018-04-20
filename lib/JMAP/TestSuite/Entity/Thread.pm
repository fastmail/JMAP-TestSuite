package JMAP::TestSuite::Entity::Thread;
use Moose;
use Carp ();
with 'JMAP::TestSuite::Entity' => {
  singular_noun => 'thread',
  properties  => [ qw(
    id
    emailIds
  ) ],
};

no Moose;
__PACKAGE__->meta->make_immutable;
