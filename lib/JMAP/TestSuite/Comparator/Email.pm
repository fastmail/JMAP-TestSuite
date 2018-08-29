package JMAP::TestSuite::Comparator::Email;
use Moose;

use Test::Deep ':v1';
use Test::Deep::JType;

use Sub::Exporter -setup => [ qw(email) ];

sub email {
  my ($overrides) = @_;

  $overrides ||= {};

  my $mailbox = any(
    [],
    array_each({
      name => any(undef, jstr),
      email => any(undef, jstr),
    }),
  );

  my $mailboxes = any([], array_each($mailbox));

  my %required = (
    id            => jstr,
    blobId        => jstr,
    threadId      => jstr,
    mailboxIds    => any({}, hash_each(jtrue)),
    size          => jnum,
    hasAttachment => jbool(),
    preview       => jstr(),
    bodyValues    => ignore, # XXX
    textBody      => ignore, # XXX
    htmlBody      => ignore, # XXX
    attachments   => ignore, # XXX
  );

  my %optional = (
    keywords      => any({}, hash_each(jtrue)),
    messageId     => any([], hash_each(jstr)),
    inReplyTo     => any([], hash_each(jstr)),
    references    => any([], hash_each(jstr)),
    sender        => any(undef, $mailboxes),
    from          => any(undef, $mailboxes),
    to            => any(undef, $mailboxes),
    cc            => any(undef, $mailboxes),
    bcc           => any(undef, $mailboxes),
    replyTo       => any(undef, $mailboxes),
    subject       => any(undef, jstr),
    receivedAt    => re('\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\dZ'),
    sentAt        => any(undef, re('\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\dZ')),
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
