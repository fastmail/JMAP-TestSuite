package JMAP::TestSuite::Entity::Email;
use Moose;
with 'JMAP::TestSuite::Entity' => {
  singular_noun => 'email',

  properties  => [ qw(
    id
    blobId
    threadId
    mailboxIds
    messageId
    keywords
    hasAttachment
    headers
    sender
    from
    to
    cc
    bcc
    replyTo
    subject
    sentAt
    receivedAt
    size
    preview
    textBody
    htmlBody
    attachments
    attachedEmails
    isUnread
    isFlagged
    isAnswered
    isDraft
  ) ],

  # I'm not sure the is* flags are still valid XXX
  # -- alh, 2018-02-20
};

use Safe::Isa;
use Data::Dumper;
use feature qw(state);
use DateTime;

sub next_time {
  state $start = DateTime->now(time_zone => 'UTC');

  # Move the clock forward a few seconds so our replies are sorted in
  # the expected order
  $start = $start->add(seconds => 2);

  return "${start}Z"; # Cheating
}

sub reply {
  my ($self, $arg) = @_;

  $arg ||= {};

  $arg->{receivedAt} //= next_time();

  $arg->{headers} ||= [];

  push @{ $arg->{headers} }, (
    'In-Reply-To' => '<' . $self->messageId->[0] . '>',
    'References'  => '<' . $self->messageId->[0] . '>',
  );

  my @mailbox_ids = keys %{ $self->mailboxIds };

  $self->add_message_to_mailboxes($self->context, $arg, @mailbox_ids);
}

sub add_message_to_mailboxes {
  my ($pkg, $context, @mailboxes) = @_;

  my $arg = {};

  if (
       $mailboxes[0]
    && ref($mailboxes[0])
    && ref($mailboxes[0]) eq 'HASH')
  {
    $arg = shift @mailboxes;
  }

  my $email = $context->email_blob(generic => $arg);

  my $batch = $pkg->import_messages(
    {
      msg => {
        blobId => $email,
        mailboxIds => { map { $_ => \1 } @mailboxes },
        ( $arg->{receivedAt}
            ? ( receivedAt => $arg->{receivedAt} )
            : ( )
        ),
      },
    },
    {
      context => $context,
    },
  );

  unless ($batch->is_entirely_successful) {
    die "Failed to import messages: " . Dumper($batch->_batch);
  }

  return $batch->result_for('msg');
}

sub import_messages {
  my ($pkg, $to_import, $extra) = @_;

  my $context = $extra->{context}
             || (blessed $pkg ? $pkg->tester  : die 'no context');

  # pre-process to_import, replacing blob hashrefs with blobs after
  # uploading
  my %upload_failure;
  for my $crid (keys %$to_import) {
    $to_import->{$crid}{$_} //= \0
      for qw(isUnread isAnswered isFlagged isDraft);

    my $blob = $to_import->{$crid}{blobId};
    next unless blessed $blob;

    if ($blob->is_success) {
      $to_import->{$crid}{blobId} = $blob->blobId;
    } else {
      delete $to_import->{$crid};
      # XXX I'm sure we can do better than this. -- rjbs, 2016-11-18
      $upload_failure{$crid} = JMAP::TestSuite::EntityError->new({
        result      => { status => $blob->http_response->code },
      });
    }
  }

  unless (keys %$to_import) {
    return JMAP::TestSuite::EntityBatch->new({
      # XXX: Problematic, because we're deleting from to_import as we go, so
      # create_spec has been corrupted by this point. -- rjbs, 2016-12-06
      create_spec => $to_import,
      batch       => { %upload_failure },
    });
  }

  my $result = $pkg->_import_batch($to_import, {
    context => $context,
  });

  return JMAP::TestSuite::EntityBatch->new({
    create_spec => $to_import,
    batch       => { %upload_failure, %$result },
  });
}

sub _import_batch {
  my ($pkg, $to_create, $extra) = @_;

  my $context = $extra->{context};

  $to_create = {
    map {; $_ => $pkg->create_args($to_create->{$_}) } keys %$to_create
  };

  my $set_res = $context->tester->request({
    using => ["ietf:jmapmail"],
    methodCalls => [
      [ "Email/import" => { emails => $to_create }, ],
    ],
  });

  unless ($set_res->sentence(0)->name eq 'Email/import') {
    die(
      "Failed to import a message: " . Dumper($set_res->as_stripped_triples)
    );
  }

  # this isn't quite a "set" sentence, but this will work anyway for created
  # and notCreated -- rjbs, 2016-11-16
  my $set_sentence = $set_res->single_sentence('Email/import')->as_set;

  my $create_errors = $set_sentence->create_errors;

  my %result;
  for my $crid ($set_sentence->not_created_ids) {
    $result{$crid} = JMAP::TestSuite::EntityError->new({
      creation_id => $crid,
      result      => $create_errors->{$crid},
    });
  }

  # TODO: detect, barf on crid appearing in both created and notCreated

  my $get_method = $pkg->get_method;
  my $get_expect = $pkg->get_result;

  my $get_res = $context->tester->request({
    using => ["ietf:jmapmail"],
    methodCalls => [
      [
        $get_method => { ids => [ $set_sentence->created_ids ] },
      ],
    ],
  });

  my $get_res_arg = $get_res->single_sentence($get_expect)
                            ->as_stripped_pair->[1];

  # TODO: do something better -- rjbs, 2016-11-15
  if ($get_res_arg->{notFound} && @{ $get_res_arg->{notFound} }) {
    require Data::Dumper;
    Carp::confess("failed to retrieve test entity data: " . Data::Dumper::Dumper($get_res_arg));
  }

  my $created = $set_sentence->created;
  my %crid_for = map {; $created->{$_}{id} => $_ } keys %$created;

  for my $item (@{ $get_res_arg->{list} }) {
    $result{ $crid_for{ $item->{id} } } = $pkg->new({
      _props  => $item,
      context => $context,
    });
  }

  # TODO: bless this into a collection
  return \%result;
}

no Moose;
__PACKAGE__->meta->make_immutable;
