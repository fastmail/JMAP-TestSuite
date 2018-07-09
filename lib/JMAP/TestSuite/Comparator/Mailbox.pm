package JMAP::TestSuite::Comparator::Mailbox;
use Moose;

use Test::Deep ':v1';
use Test::Deep::JType;

use Sub::Exporter -setup => [ qw(mailbox) ];

sub mailbox {
  my ($req_override, $opt_override) = @_;

  $req_override ||= {};
  $opt_override ||= {};

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
      )
    }),

    %$req_override,
  );

  my %optional = (
    parentId  => any(jstr, undef),
    role      => any(jstr, undef), # xxx enum allowed values?
    sortOrder => any(jnum, undef),

    %$opt_override,
  );

  # superhashof ensures all of the keys exist and match
  # subhashof ensures that the provided keys are only ones we expect
  # (and their values match too)
  # This way we can say "this set of things is required" and "this
  # set of things is optional" since the server may omit things with
  # default values
  return all(
    superhashof(\%required),
    subhashof({ %required, %optional })
  );
}

no Moose;
__PACKAGE__->meta->make_immutable;
