package JMAP::TestSuite::Entity::Message;
use Moose;
with 'JMAP::TestSuite::Entity' => {
  plural_noun => 'messages',

  # TODO: flesh out
  properties  => [ qw(id blobId threadId mailboxIds subject) ],
};

sub import_messages {
  my ($pkg, $to_import, $extra) = @_;

  my $tester  = $extra->{tester}  || (blessed $pkg ? $pkg->tester  : die 'no tester');
  my $account = $extra->{account} || (blessed $pkg ? $pkg->account : die 'no account');

  # pre-process to_import, replacing blob hashrefs with blobs after
  # uploading
  my %upload_failure;
  for my $crid (keys %$to_import) {
    my $blob = $to_import->{$crid}{blobId};
    next unless blessed $blob;
    my $upload = $tester->upload('message/rfc822', \$blob->as_string);

    if ($upload->is_success) {
      $to_import->{$crid}{blobId} = $upload->blobId;
    } else {
      delete $to_import->{$crid};
      $upload_failure{$crid} = JMAP::TestSuite::EntityError->new({
        creation_id => $crid,
        result      => { status => $upload->http_response->code },
      });
    }
  }

  my $result = $pkg->_import_batch($to_import, {
    tester  => $tester,
    account => $account,
  });

  return JMAP::TestSuite::EntityBatch->new({
    batch => { %upload_failure, %$result },
  });
}

sub _import_batch {
  my ($pkg, $to_create, $extra) = @_;

  my $tester  = $extra->{tester};
  my $account = $extra->{account};

  $to_create = {
    map {; $_ => $pkg->create_args($to_create->{$_}) } keys %$to_create
  };

  my $set_res = $tester->request([
    [ importMessages => { messages => $to_create } ]
  ]);

  # this isn't quite a "set" sentence, but this will work anyway for created
  # and notCreated -- rjbs, 2016-11-16
  my $set_sentence = $set_res->single_sentence('messagesImported')->as_set;

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

  my $get_res = $tester->request([
    [
      $get_method => { ids => [ $set_sentence->created_ids ] },
    ],
  ]);

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
      account => $account,
      tester  => $tester,
    });
  }

  # TODO: bless this into a collection
  return \%result;
}

no Moose;
__PACKAGE__->meta->make_immutable;
