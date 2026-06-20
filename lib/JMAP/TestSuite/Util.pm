use strict;
use warnings;
package JMAP::TestSuite::Util;

use Sub::Exporter -setup => [ qw(
  batch_ok
  email
  mailbox
  calendar
  thread
  get_parts multipart part parts cmultipart cpart
) ];

use Test::Deep ':v1';
use Test::Deep::JType;
use Test::More;

use JMAP::TestSuite::Comparator::Email qw(email);
use JMAP::TestSuite::Comparator::Mailbox qw(mailbox);
use JMAP::TestSuite::Comparator::Thread qw(thread);
use JMAP::TestSuite::Comparator::Calendar qw(calendar);

sub batch_ok {
  my ($batch) = @_;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  if ($batch->has_create_spec) {
    is_deeply(
      [ sort $batch->result_ids ],
      [ sort $batch->creation_ids ],
      "batch has results for every creation id and nothing more",
    );
  }

  # TODO: every non-error result has properties superhash of create spec

  if ($ENV{JMAP_STRICT_PROPERTIES}) {
    my @broken_ids = grep {;
      !  $batch->result_for($_)->is_error
      && $batch->result_for($_)->unknown_properties
    } $batch->result_ids;

    if (@broken_ids) {
      fail("some batch results have unknown properties");
      for my $id (@broken_ids) {
        diag("  $id has unknown properties: "
            . join(q{, }, $batch->result_for($id)->unknown_properties)
        );
      }
    } else {
      pass("no unknown properties in batch results");
    }
  }
}

# Some common parts used in Email/get tests. Taken from the example message
# structure just above this:
# https://github.com/jmapio/jmap/blob/master/spec/mail/message.mdown#emailget
sub get_parts {
  return (
    A => {
      blobId      => jstr(),
      charset     => 'us-ascii', # No CT, so default charset
      cid         => undef,      # not provided
      disposition => undef,      # not provided
      language    => any([], undef), # not provided
      location    => undef,      # not provided
      name        => undef,      # not provided
      partId      => jstr(),
      size        => 21,         # Size if downloaded, includes CR
      type        => 'text/plain', # No CT so default type
    },

    B => {
      blobId      => jstr(),
      charset     => 'us-ascii', # not provided, so default us-ascii
      cid         => 'foo4*foo1@bar.net',
      disposition => 'inline',
      language    => bag(qw(en de)),
      location    => 'foo/bar',
      name        => 'b.txt',    # Content-Disposition filename
      partId      => jstr(),
      size        => 21,         # Size if downloaded, includes CR
      type        => 'text/plain', # not provided, so default text/plain
    },

    C => {
      blobId      => jstr(),
      charset     => undef,
      cid         => undef,      # not provided
      disposition => 'inline',
      language    => any([], undef), # not provided
      location    => undef,      # not provided
      name        => 'c.jpg',    # Content-Type name
      partId      => jstr(),
      size        => jnum(),
      type        => 'image/jpeg',
    },

    D => {
      blobId      => jstr(),
      charset     => 'iso-8859-1', # Content-Type provided
      cid         => undef,      # not provided
      disposition => 'inline',
      language    => any([], undef), # not provided
      location    => undef,      # not provided
      name        => undef,      # not provided
      partId      => jstr(),
      size        => 21,         # Size if downloaded, includes CR
      type        => 'text/plain',
    },

    E => {
      blobId      => jstr(),
      charset     => 'us-ascii', # CT present but no charset
      cid         => undef,      # not provided
      disposition => undef,
      language    => any([], undef), # not provided
      location    => undef,      # not provided
      name        => undef,      # not provided
      partId      => jstr(),
      size        => 49,         # Size if downloaded, includes CR
      type        => 'text/html',
    },

    F => {
      blobId      => jstr(),
      charset     => undef,
      cid         => undef,      # not provided
      disposition => 'inline',
      language    => any([], undef), # not provided
      location    => undef,      # not provided
      name        => 'f.jpg',    # Content-Type name
      partId      => jstr(),
      size        => jnum(),
      type        => 'image/jpeg',
    },

    G => {
      blobId      => jstr(),
      charset     => undef,
      cid         => undef,      # not provided
      disposition => 'attachment',
      language    => any([], undef), # not provided
      location    => undef,      # not provided
      name        => 'g.jpg',    # Content-Type name
      partId      => jstr(),
      size        => jnum(),
      type        => 'image/jpeg',
    },

    H => {
      blobId      => jstr(),
      charset     => undef,
      cid         => undef,      # not provided
      disposition => undef,
      language    => any([], undef), # not provided
      location    => undef,      # not provided
      name        => undef,
      partId      => jstr(),
      size        => jnum(),
      type        => 'application/x-excel',
    },

    J => {
      blobId      => jstr(),
      charset     => undef,
      cid         => undef,      # not provided
      disposition => undef,
      language    => any([], undef), # not provided
      location    => undef,      # not provided
      name        => undef,
      partId      => jstr(),
      size        => jnum(),
      type        => 'message/rfc822',
    },

    K => {
      blobId      => jstr(),
      charset     => 'us-ascii', # CT present but no charset
      cid         => undef,      # not provided
      disposition => 'inline',
      language    => any([], undef), # not provided
      location    => undef,      # not provided
      name        => undef,      # not provided
      partId      => jstr(),
      size        => 21,         # Size if downloaded, includes CR
      type        => 'text/plain',
    },
  );
}

# For examining responses
sub multipart {
  my ($type, $subparts) = @_;

  return {
    blobId      => undef,
    charset     => undef,
    cid         => undef,
    disposition => undef,
    language    => any([], undef),
    location    => undef,
    name        => undef,
    partId      => undef,
    size        => 0,
    type        => "multipart/$type",
    subParts    => $subparts,
  };
}

sub part {
  my ($type) = @_;

  return {
    blobId      => jstr(),
    charset     => ignore(),
    cid         => undef,      # not provided
    disposition => undef,      # not provided
    language    => any([], undef), # not provided
    location    => undef,      # not provided
    name        => undef,      # not provided
    partId      => jstr(),
    size        => jnum(),
    type        => $type,
  };
}

sub parts {
  map { part($_) } @_;
}

# For creating requests
sub cmultipart {
  my ($type, $subparts) = @_;

  return Email::MIME->create(
    attributes => { content_type => "multipart/$type", },
    parts => $subparts,
  );
}

sub cpart {
  my ($type, $data) = @_;

  Email::MIME->create(
    attributes => {
      content_type => $type,
    },
    body => $data // "",
  );
}

1;
