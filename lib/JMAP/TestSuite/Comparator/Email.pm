package JMAP::TestSuite::Comparator::Email;
use Moose;

use Test::Deep ':v1';
use Test::Deep::JType;
use Test::Deep::HashRec;

use Sub::Exporter -setup => [ qw(email client_keywords) ];

sub email {
  my ($overrides) = @_;

  $overrides ||= {};

  # RFC 8621 S4.1.2.3: an EmailAddress has "name" (String|null) and "email"
  # (String); address properties are EmailAddress[]|null.
  my $mailboxes = array_each({
    name  => any(undef, jstr),
    email => jstr,
  });

  # RFC 8621 S4.1.3: message id properties are String[]|null.
  my $message_ids = any(undef, array_each(jstr));

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
    messageId     => $message_ids,
    inReplyTo     => $message_ids,
    references    => $message_ids,
    sender        => any(undef, $mailboxes),
    from          => any(undef, $mailboxes),
    to            => any(undef, $mailboxes),
    cc            => any(undef, $mailboxes),
    bcc           => any(undef, $mailboxes),
    replyTo       => any(undef, $mailboxes),
    subject       => any(undef, jstr),
    receivedAt    => re('\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d*[1-9])?Z'),
    # RFC 8621 S4.1.3: sentAt is a Date, so any offset is allowed.
    sentAt        => any(undef, re('\A\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d*[1-9])?(?:Z|[+-]\d\d:\d\d)\z')),
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

# Exactly the keywords the client set (none, by default). RFC 9979 section 4
# lets the server set the mutually exclusive attachment-detection keywords
# itself, so those two may also appear; nothing else may.
sub client_keywords {
  my ($required) = @_;

  return hashrec({
    required => { %{ $required || {} } },
    optional => {
      q{$hasattachment}   => jtrue,
      q{$hasnoattachment} => jtrue,
    },
  });
}

no Moose;
__PACKAGE__->meta->make_immutable;
