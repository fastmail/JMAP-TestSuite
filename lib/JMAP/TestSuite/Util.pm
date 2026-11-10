use strict;
use warnings;
package JMAP::TestSuite::Util;

use Sub::Exporter -setup => [ qw(
  batch_ok
  fetch_session
  foreign_account_not_found_ok
  cannot_calculate_changes_ok
  email_create_invalid_or_repaired
  invalid_properties
  email
  client_keywords
  mailbox
  calendar
  calendar_event
  address_book
  contact_card
  thread
  body_lists_ok
  get_parts multipart part parts cmultipart cpart
) ];

use Test::Deep ':v1';
use Test::Deep::JType;
use Test::More;
use JSON ();

use JMAP::TestSuite::Comparator::Email qw(email client_keywords);
use JMAP::TestSuite::Comparator::Mailbox qw(mailbox);
use JMAP::TestSuite::Comparator::Thread qw(thread);
use JMAP::TestSuite::Comparator::Calendar qw(calendar);
use JMAP::TestSuite::Comparator::CalendarEvent qw(calendar_event);
use JMAP::TestSuite::Comparator::AddressBook qw(address_book);
use JMAP::TestSuite::Comparator::ContactCard qw(contact_card);

=head1 FUNCTIONS

=head2 fetch_session

  my $session = fetch_session($tester) or return;

GETs and decodes the session resource (RFC 8620 section 2), from the tester's
C<authentication_uri> when the adapter set one and otherwise from C<api_uri>.
Nothing in the RFC makes those the same URL, so a test must not GET
C<api_uri> itself and call the result the session.

=cut

sub fetch_session {
  my ($tester) = @_;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my $uri = $tester->has_authentication_uri
          ? $tester->authentication_uri
          : $tester->api_uri;
  my $res = $tester->ua->lwp->get($uri, $tester->_maybe_auth_header);
  ok($res->is_success, "GET $uri (session resource)")
    or diag($res->status_line);

  my $data = eval { JSON->new->decode($res->decoded_content) };
  ok($data, 'session resource is JSON')
    or diag("Invalid json?: " . $res->decoded_content);

  return $data;
}

=head2 foreign_account_not_found_ok

  foreign_account_not_found_ok($account, $other, [
    [ 'Foo/get'  => { ids => [] } ],
    [ 'Foo/copy' => { fromAccountId => 'SELF', accountId => 'OTHER' } ],
  ]);

Asserts that every listed call, made as C<$account> but naming C<$other>'s
accountId, fails with C<accountNotFound> (RFC 8620 section 3.6.2).  C<$other> exists
on the server but is outside C<$account>'s session, and must be reported the
same way as an id that does not exist at all.  A /copy whose C<fromAccountId>
is the foreign one must fail with C<fromAccountNotFound> instead (sections 5.4
and 6.3).

Each call is C<[ $method, \%args ]>.  C<accountId> is set to the foreign id
unless given.  The strings C<'SELF'> and C<'OTHER'> in C<accountId> or
C<fromAccountId> are replaced with the caller's and the foreign id, so a
/copy can be tested in both directions.

=cut

sub foreign_account_not_found_ok {
  my ($account, $other, $calls) = @_;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my $tester  = $account->tester;
  my $foreign = $other->accountId;
  my $mine    = $account->accountId;

  isnt($foreign, $mine, "the other account ($foreign) is not this one ($mine)")
    or return;

  # Where the tester knows its session's accounts, check the target is outside
  # them, or the test proves nothing.
  my %visible = $tester->accounts;
  if (%visible) {
    ok(!$visible{$foreign}, "account $foreign is not in this session") or return;
  }

  for my $call (@$calls) {
    my ($method, $args) = @$call;
    my %args = %{ $args || {} };
    for my $k (qw(accountId fromAccountId)) {
      next unless exists $args{$k};
      $args{$k} = $foreign if $args{$k} eq 'OTHER';
      $args{$k} = $mine    if $args{$k} eq 'SELF';
    }
    $args{accountId} = $foreign unless exists $args{accountId};

    # A state string is opaque, and a server may check its shape before it
    # looks at accountId. RFC 8620 sets no precedence between the two errors,
    # so give it a real state from the caller's own account: the test is
    # about the account, not the state.
    my ($type) = $method =~ m{^(\w+)/};
    for my $pair ([sinceState => "$type/get", 'state'], [sinceQueryState => "$type/query", 'queryState']) {
      my ($arg, $own_method, $prop) = @$pair;
      next unless exists $args{$arg} && $args{$arg} eq '0';
      my $own = eval { $tester->request([[ $own_method => { accountId => $mine } ]]) };
      my $state = eval { $own->single_sentence($own_method)->arguments->{$prop} };
      $args{$arg} = $state if defined $state;
    }

    my $desc = join ' ', $method, map { "$_=" . ($args{$_} eq $foreign ? 'OTHER' : 'SELF') }
                 grep { exists $args{$_} } qw(fromAccountId accountId);

    my $res = $tester->request([[ $method => \%args ]]);
    ok($res->is_success, "$desc: request completed")
      or diag(explain($res->response_payload)), next;

    my $s = $res->sentence(0);
    is($s->name, 'error', "$desc: is an error")
      or diag explain $res->as_stripped_triples;

    # A method the server does not implement at all is unknownMethod before
    # any account is looked at. Accept that only when the same call against
    # the caller's own account is unknownMethod too, so a server cannot hide
    # a foreign account behind it.
    if (($s->arguments->{type} // q{}) eq q{unknownMethod}) {
      my $own = $tester->request([[ $method => { %args, accountId => $mine } ]]);
      my $own_type = eval { $own->sentence(0)->arguments->{type} } // q{};
      if ($own_type eq q{unknownMethod}) {
        note("$method is not implemented by this server; nothing to check");
        next;
      }
    }

    my $want = ($args{fromAccountId} // '') eq $foreign && $args{accountId} ne $foreign
             ? 'fromAccountNotFound'
             : 'accountNotFound';
    jcmp_deeply(
      $s->arguments,
      superhashof({ type => $want }),
      "$desc: $want",
    ) or diag explain $res->as_stripped_triples;
  }
}

=head2 invalid_properties

  jcmp_deeply($err, invalid_properties(qw(mailboxIds keywords)));

A comparator for an C<invalidProperties> SetError.  RFC 8620 section 5.3 says
the error "SHOULD also have a property called C<properties>" listing the
invalid ones, so it may be absent; when present it must name each given
property, as itself, as a path inside it (C<myRights/mayDelete> for
C<myRights>), or as a path containing it.  Order and extra entries do not
matter.

=cut

sub invalid_properties {
  my @want = @_;

  return code(sub {
    my ($err) = @_;
    return (0, "not a SetError object") unless ref $err eq 'HASH';
    my $type = $err->{type} // 'undef';
    return (0, "type is $type, not invalidProperties") unless $type eq 'invalidProperties';

    my $got = $err->{properties};
    return 1 unless defined $got;
    return (0, "properties is not an array") unless ref $got eq 'ARRAY';

    for my $w (@want) {
      next if grep {; $_ eq $w || index($_, "$w/") == 0 || index($w, "$_/") == 0 } @$got;
      return (0, "properties [@$got] does not name $w");
    }
    return 1;
  });
}

=head2 body_lists_ok

  my $label_for = body_lists_ok($email, {
    leaves    => [ A => $PART{A}, B => $PART{B}, ... ],
    suggested => {
      textBody    => [qw(A B C D K)],
      htmlBody    => [qw(A E K)],
      attachments => [qw(C F G H J)],
    },
  });

Checks, as one subtest, the textBody, htmlBody and attachments of C<$email>
(an Email/get result that includes bodyStructure and all three lists) against
RFC 8621 section 4.1.4.  C<leaves> labels the non-multipart parts of
bodyStructure in depth-first order and gives each one's expectation.

The section says the decomposition "is not mandated", so what is checked is:
every textBody and htmlBody part is a leaf of bodyStructure of type
text/plain, text/html, image/*, audio/* or video/*; attachments is exactly the
depth-first list of leaves that are in neither list, or are image/audio/video
and not in both; and every listed part matches its leaf's expectation.
Whether the lists equal C<suggested>, the result of the section's suggested
algorithm, is only reported with C<note>.

Returns a hashref from partId to label.

=cut

sub body_lists_ok {
  my ($email, $arg) = @_;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my %label_for;

  subtest "textBody, htmlBody and attachments" => sub {
    my @leaves;
    my $walk;
    $walk = sub {
      my ($part) = @_;
      return push @leaves, $part unless ($part->{type} // '') =~ m{\Amultipart/}i;
      $walk->($_) for @{ $part->{subParts} || [] };
    };
    $walk->($email->{bodyStructure} || {});

    my @pairs = @{ $arg->{leaves} };
    is(@leaves, @pairs / 2, "bodyStructure has the expected number of leaf parts")
      or return diag explain $email->{bodyStructure};

    my (@order, %expect_for, %is_media);
    for my $i (0 .. $#leaves) {
      my ($label, $expect) = @pairs[ 2 * $i, 2 * $i + 1 ];
      push @order, $label;
      $label_for{ $leaves[$i]{partId} // '' } = $label;
      $expect_for{$label} = $expect;
      $is_media{$label} = ($leaves[$i]{type} // '') =~ m{\A(?:image|audio|video)/}i;
    }

    my %got;
    for my $list (qw(textBody htmlBody attachments)) {
      for my $part (@{ $email->{$list} || [] }) {
        my $label = $label_for{ $part->{partId} // '' };
        ok(defined $label, "$list part is a leaf of bodyStructure")
          or diag(explain($part)), next;
        push @{ $got{$list} }, $label;

        jcmp_deeply($part, $expect_for{$label}, "$list part $label looks right");
        next if $list eq 'attachments';

        like(
          $part->{type},
          qr{\A(?:text/plain|text/html|image/.+|audio/.+|video/.+)\z}i,
          "$list part $label is of a type allowed in $list",
        );
      }
    }

    my %in = map {; my $l = $_; $l => { map {; $_ => 1 } @{ $got{$l} || [] } } }
             qw(textBody htmlBody);
    my @want = grep {;
         (! $in{textBody}{$_} && ! $in{htmlBody}{$_})
      || ($is_media{$_} && ! ($in{textBody}{$_} && $in{htmlBody}{$_}))
    } @order;

    is(
      "@{ $got{attachments} || [] }",
      "@want",
      "attachments are the leaves not in textBody or htmlBody, plus media not in both",
    );

    for my $list (qw(textBody htmlBody attachments)) {
      my $want = $arg->{suggested}{$list} // next;
      my $have = "@{ $got{$list} || [] }";
      note(
        $have eq "@$want"
          ? "$list matches the RFC 8621 S4.1.4 suggested algorithm"
          : "$list is [$have]; the RFC 8621 S4.1.4 suggested algorithm gives [@$want]"
      );
    }
  };

  return \%label_for;
}



=head2 email_create_invalid_or_repaired

  email_create_invalid_or_repaired($tester, \%email, \%get_args, sub {
    my ($email) = @_;
    ...
  }, $desc);

Creates C<\%email>, which breaks one of the RFC 8621 section 4.6 creation
rules.  The server "SHOULD" reject it with C<invalidProperties>, but "MAY
choose to modify the Email ... to comply with its requirements instead", so
either passes: a rejection must be C<invalidProperties>, and a created Email
is fetched with C<\%get_args> and handed to the callback, which asserts the
repair does comply.

=cut

sub email_create_invalid_or_repaired {
  my ($tester, $email, $get_args, $check, $desc) = @_;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my $res = $tester->request([[ 'Email/set' => { create => { new => $email } } ]]);
  my $set = $res->single_sentence('Email/set')->arguments;

  if (my $err = $set->{notCreated}{new}) {
    is($err->{type}, 'invalidProperties', "$desc: rejected with invalidProperties")
      or diag explain $err;
    return;
  }

  my $id = $set->{created}{new}{id};
  ok($id, "$desc: created, so the server repaired it")
    or return diag explain $res->as_stripped_triples;

  my $get = $tester->request([[ 'Email/get' => { ids => [ $id ], %$get_args } ]]);
  my $got = $get->single_sentence('Email/get')->arguments->{list}[0];
  ok($got, "$desc: the repaired Email can be fetched")
    or return diag explain $get->as_stripped_triples;

  subtest "$desc: the repaired Email complies" => sub { $check->($got) };
}

=head2 cannot_calculate_changes_ok

  my $res = $tester->request([[ "Foo/changes" => { sinceState => $state } ]]);
  return if cannot_calculate_changes_ok($res);

RFC 8620 S5.2 lets a server answer a /changes (or /queryChanges) with
C<cannotCalculateChanges> whenever it cannot work them out.  That is within
the spec, if inefficient: this notes it, passes, and returns true, so the
caller can skip the checks it cannot make.  Any other answer returns false
and is the caller's to judge.

=cut

sub cannot_calculate_changes_ok {
  my ($res) = @_;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my $s = eval { $res->single_sentence } or return 0;
  return 0 unless $s->name eq 'error'
               && ($s->arguments->{type} // '') eq 'cannotCalculateChanges';
  note("inefficient but within the spec: cannotCalculateChanges");
  pass("cannotCalculateChanges is allowed (RFC 8620 S5.2)");
  return 1;
}


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
  my %parts = (
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

  return map {; $_ => _leaf($parts{$_}) } keys %parts;
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
    size        => jnum(),  # RFC 8621 4.1.4 defines size via blobId, which is null for multipart
    type        => "multipart/$type",
    subParts    => $subparts,
  };
}

sub part {
  my ($type) = @_;

  return _leaf({
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
  });
}

sub parts {
  map { part($_) } @_;
}

# RFC 8621 S4.1.4: subParts is "EmailBodyPart[]|null" and only meaningful for
# multipart/*, so a leaf may omit it or give null or [].
sub _leaf {
  my ($expect) = @_;

  return code(sub {
    my ($got) = @_;
    return (0, "not an EmailBodyPart object") unless ref $got eq 'HASH';

    my %got = %$got;
    my $sub_parts = delete $got{subParts};
    return (0, "leaf part has non-empty subParts")
      if defined $sub_parts && ! (ref $sub_parts eq 'ARRAY' && ! @$sub_parts);

    my ($ok, $stack) = Test::Deep::cmp_details(\%got, $expect);
    return $ok || (0, Test::Deep::deep_diag($stack));
  });
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
