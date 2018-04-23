use strict;
use warnings;
package JMAP::TestSuite::Entity {
  use MooseX::Role::Parameterized;

  parameter properties => (
    is  => 'ro',
    isa => 'ArrayRef[Str]',
    required => 1,
  );

  parameter singular_noun => (
    is => 'ro',
    required => 1,
  );

  role {
    my $param = shift;

    with 'JMAP::TestSuite::EntityRole::Common';

    my $noun = $param->singular_noun;
    method get_method => sub { "\u$noun/get" };
    method get_result => sub { "\u$noun/get" };
    method set_method => sub { "\u$noun/set" };
    method set_result => sub { "\u$noun/set" };

    for my $property (@{ $param->properties }) {
      method $property => sub {
        Carp::croak("Cannot assign a value to a read-only accessor") if @_ > 1;
        return  $_[0]->_props->{$property};
      };
    }

    has _props => (
      is       => 'ro',
      traits   => [ 'Hash' ],
      handles  => {
        value_for => 'get',
      },
      required => 1,
    );

    has _unknown_props => (
      is   => 'ro',
      lazy => 1,
      traits  => [ 'Hash' ],
      handles => {
        unknown_properties => 'keys',
      },
      default => sub {
        my ($self) = @_;
        my %known   = map {; $_ => 1 } @{ $param->properties };
        my %props   = %{ $self->_props };
        my %unknown = map {; $known{$_} ? () : ($_ => $props{$_}) } keys %props;
        return \%unknown;
      },
    );
  }
}

package JMAP::TestSuite::EntityRole::Common {
  use Moose::Role;

  sub is_error { 0 }

  has context => (
    is => 'ro',
    required => 1,
    handles  => [ qw(account accountId tester clear_tester) ],
  );

  no Moose::Role;

  sub create_args {
    my ($self, $arg) = @_;
    return { %$arg };
  }

  sub _create_batch {
    my ($pkg, $to_create, $extra) = @_;

    # We're not offering a way to execute a create with a different accountId,
    # which maybe is okay for now.  In the future, we might need entities to
    # have both an account and accountId, with the account only implying the
    # accountId *by default*. -- rjbs, 2016-11-15

    my $context = $extra->{context}
               || (blessed $pkg ? $pkg->tester  : die 'no context');

    my $set_method = $pkg->set_method;
    my $set_expect = $pkg->set_result;

    $to_create = {
      map {; $_ => $pkg->create_args($to_create->{$_}) } keys %$to_create
    };

    my $set_res = $context->tester->request({
      using => ["ietf:jmapmail"],
      methodCalls => [
        [ $set_method => { create => $to_create } ],
      ],
    });

    my $set_sentence = $set_res->single_sentence($set_expect)->as_set;

    my $create_errors = $set_sentence->create_errors;

    my %result;
    for my $crid ($set_sentence->not_created_ids) {
      $result{$crid} = JMAP::TestSuite::EntityError->new({
        result      => $create_errors->{$crid},
      });
    }

    if (
      my @unexpected = grep {; ! exists $to_create->{$_} }
                       $set_sentence->created_creation_ids
    ) {
      confess("$set_expect returned  unexpected creation ids: @unexpected");
    }

    # TODO: detect, barf on crid appearing in both created and notCreated

    my $get_method = $pkg->get_method;
    my $get_expect = $pkg->get_result;

    my $get_res = $context->tester->request({
      using => ["ietf:jmapmail"],
      methodCalls => [
        [ $get_method => { ids => [ $set_sentence->created_ids ] }, ],
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

    return \%result;
  }

  sub create {
    my ($pkg, $item_to_create, $extra) = @_;
    my $result = $pkg->_create_batch({ a => $item_to_create, $extra });
    return $result->{a};
  }

  sub create_batch {
    my ($pkg, $to_create, $extra) = @_;
    my $result = $pkg->_create_batch($to_create, $extra);
    return JMAP::TestSuite::EntityBatch->new({
      batch       => $result,
      create_spec => $to_create,
    });
  }

  sub _retrieve_batch {
    my ($pkg, $ids, $extra) = @_;

    my $context = $extra->{context}
               || (blessed $pkg ? $pkg->tester  : die 'no context');

    my $get_method = $pkg->get_method;
    my $get_expect = $pkg->get_result;

    my $get_res = $context->tester->request({
      using => ["ietf:jmapmail"],
      methodCalls => [
        [ $get_method => { ids => [ @$ids ] }, ],
      ],
    });

    my $get_res_arg = $get_res->single_sentence($get_expect)
                              ->as_stripped_pair->[1];

    my %result;
    for my $nf_id (@{ $get_res_arg->{notFound} // [] }) {
      $result{$nf_id} = JMAP::TestSuite::EntityError->new({
        result => "not found",
      });
    }

    for my $item (@{ $get_res_arg->{list} }) {
      $result{ $item->{id} } = $pkg->new({
        _props  => $item,
        context => $context,
      });
    }

    return \%result;
  }

  sub retrieve_batch {
    my ($pkg, $ids, $extra) = @_;
    my $result = $pkg->_retrieve_batch($ids, $extra);
    return JMAP::TestSuite::EntityBatch->new({ batch => $result });
  }

  sub retrieve { ... }

  sub get_state {
    my ($pkg, $extra) = @_;

    my $context = $extra->{context}
               || (blessed $pkg ? $pkg->tester  : die 'no context');

    my $get_method = $pkg->get_method;
    my $get_expect = $pkg->get_result;

    my $get_res = $context->tester->request({
      using => ["ietf:jmapmail"],
      methodCalls => [
        [ $get_method => { ids => [], }, ],
      ],
    });

    my $get_res_arg = $get_res->single_sentence($get_expect)
                              ->as_stripped_pair->[1];

    unless (exists $get_res_arg->{state}) {
      die "No state found for $get_expect\n";
    }

    return $get_res_arg->{state};
  }

  sub destroy {
    my ($self) = @_;

    my $set_method = $self->set_method;
    my $set_expect = $self->set_result;

    my $set_res = $self->tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        $set_method => {
          destroy => [ $self->id ],
        },
      ]],
    });

    my $set_res_arg = $set_res->single_sentence($set_expect)->arguments;
    unless (
         $set_res_arg->{destroyed}
      && $set_res_arg->{destroyed}[0] eq $self->id
    ) {
      require Data::Dumper;
      Carp::confess(
          "failed to destroy test entity: "
        . Data::Dumper::Dumper($set_res->as_stripped_triples)
      );
    }

    return;
  }

  sub update {
    my ($self, $updates) = @_;

    my $set_method = $self->set_method;
    my $set_expect = $self->set_result;

    my $set_res = $self->tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        $set_method => {
          update => {
            $self->id => $updates,
          },
        },
      ]],
    });

    my $set_res_arg = $set_res->single_sentence($set_expect)->arguments;
    unless (
         $set_res_arg->{updated}
      && exists $set_res_arg->{updated}{$self->id}
    ) {
      require Data::Dumper;
      Carp::confess(
          "failed to update test entity: "
        . Data::Dumper::Dumper($set_res->as_stripped_triples)
      );
    }

    return;
  }
}

# retrieve
# retrieve_batch
# update
# update_batch
# destroy
# destroy_batch
#
# accessors
# accountId
# refresh

package JMAP::TestSuite::EntityError {
  use Moose;

  sub is_error { 1 }

  has result => (is => 'ro', required => 1);

  sub error_type { $_[0]->result->{type} }

  no Moose;
}

package JMAP::TestSuite::EntityBatch {
  use Moose;

  has create_spec => (
    isa => 'HashRef',
    traits  => [ 'Hash' ],
    handles => {
      creation_ids => 'keys',
      spec_for     => 'get',
    },
    predicate => 'has_create_spec',
  );

  has batch => (
    isa => 'HashRef',
    required => 1,
    traits   => [ 'Hash' ],
    reader   => '_batch',
    handles  => {
      result_for  => 'get',
      result_ids  => 'keys',
      all_results => 'values',
    },
  );

  sub is_entirely_successful {
    return ! grep {; $_->is_error } $_[0]->all_results;
  }

  sub retrieve {
    my ($self) = @_;
    # return a new batch with the same keys, dropping failures, and with the
    # new values gotten by retrieving by entity id
    ...;
  }

  no Moose;
}

1;
