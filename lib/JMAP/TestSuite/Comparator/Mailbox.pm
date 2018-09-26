package JMAP::TestSuite::Comparator::Mailbox;
use Moose;

use Test::Deep ':v1';
use Test::Deep::JType;
use Test::Deep::HashRec;

use Sub::Exporter -setup => [ qw(mailbox) ];

sub mailbox {
  my ($overrides) = @_;

  $overrides ||= {};

  my %required = (
    id            => jstr,
    name          => jstr,
    totalEmails   => jnum,
    unreadEmails  => jnum,
    totalThreads  => jnum,
    unreadThreads => jnum,
    myRights      => superhashof({
      map {
        $_ => jbool(),
      } qw(
        mayReadItems
        mayAddItems
        mayRemoveItems
        maySetSeen
        maySetKeywords
        mayCreateChild
        mayRename
        mayDelete
        maySubmit
        mayAdmin
      )
    }),
  );

  my %optional = (
    parentId  => any(jstr, undef),
    role      => any(jstr, undef), # xxx enum allowed values?
    sortOrder => any(jnum, undef),
    shareWith => undef,
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
