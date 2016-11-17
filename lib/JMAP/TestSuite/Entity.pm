use strict;
use warnings;
package JMAP::TestSuite::Entity {
  use MooseX::Role::Parameterized;

  parameter properties => (
    is  => 'ro',
    isa => 'ArrayRef[Str]',
    required => 1,
  );

  parameter plural_noun => (
    is => 'ro',
    required => 1,
  );

  parameter can_create => (
    is => 'ro',
    default => 1,
  );

  role {
    my $param = shift;

    with(
      ($param->can_create
        ? 'JMAP::TestSuite::EntityRole::Create'
        : 'JMAP::TestSuite::EntityRole::Common'),
    );

    my $noun = $param->plural_noun;
    method get_method => sub { "get\u$noun" };
    method get_result => sub { "$noun" };
    method set_method => sub { "set\u$noun" };
    method set_result => sub { "${noun}Set" };

    for my $property (@{ $param->properties }) {
      method $property => sub {
        Carp::croak("Cannot assign a value to a read-only accessor") if @_ > 1;
        return  $_[0]->_props->{$property};
      };
    }
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

  has _props => (
    is => 'ro',
    required => 1,
  );

  no Moose::Role;
}

package JMAP::TestSuite::EntityRole::Create {
  use Moose::Role;
  with 'JMAP::TestSuite::EntityRole::Common';

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

    my $set_res = $context->tester->request([
      [ $set_method => { create => $to_create } ]
    ]);

    my $set_sentence = $set_res->single_sentence($set_expect)->as_set;

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

    my $get_res = $context->tester->request([
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
        context => $context,
      });
    }

    # TODO: bless this into a collection
    return \%result;
  }

  sub create {
    my ($pkg, $item_to_create, $extra) = @_;
    my $result = $pkg->_create_batch({ a => $item_to_create, $extra });
    return $result->{a};
  }

  sub create_list {
    my ($pkg, $to_create_array, $extra) = @_;
    my %to_create = map {; $_ => $to_create_array->[$_] }
                    keys @$to_create_array;

    my $result = $pkg->_create_batch(\%to_create, $extra);
    return @$result{ sort { $a <=> $b } keys %$result };
  }

  sub create_batch {
    my ($pkg, $to_create, $extra) = @_;
    my $result = $pkg->_create_batch($to_create, $extra);
    return JMAP::TestSuite::EntityBatch->new({ batch => $result });
  }
}

# create
# create_batch
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
# instance (TestSuite::Instance)

package JMAP::TestSuite::EntityError {
  use Moose;

  sub is_error { 1 }

  has creation_id => (is => 'ro', required => 1);
  has result      => (is => 'ro', required => 1);

  sub error_type { $_[0]->result->{type} }

  no Moose;
}

package JMAP::TestSuite::EntityBatch {
  use Moose;

  has batch => (
    isa => 'HashRef',
    required => 1,
    traits   => [ 'Hash' ],
    reader   => '_batch',
    handles  => {
      result_for  => 'get',
      all_results => 'values',
    },
  );

  sub is_entirely_successful {
    return ! grep {; $_->is_error } $_[0]->all_results;
  }

  no Moose;
}

1;
