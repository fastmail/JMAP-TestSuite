use v5.14.0;
use warnings;

package jmaptest;

use Import::Into ();

use Test::Routine ();
use Test::Routine::Util ();
use JMAP::TestSuite::Util ();

use Test::Deep ();
use Test::Deep::JType ();
use Test::More ();
use JSON ();
use JSON::Typist ();
use Test::Abortable ();

sub import {
  my $caller = caller;

  strict->import;
  warnings->import;

  JSON->import::into($caller);
  Test::Deep->import::into($caller, ':v1');
  Test::Deep::JType->import::into($caller);
  Test::More->import::into($caller);
  Test::Abortable->import::into($caller);
  Moose::Meta::Role->create($caller);

  JMAP::TestSuite::Util->import::into($caller, qw(batch_ok));
  Moose::Util::apply_all_roles($caller, 'JMAP::TestSuite::Tester');

  Sub::Install::install_sub({
    into => $caller,
    as   => 'test',
    code => \&jmaptest,
  });

  Sub::Install::install_sub({
    into => $caller,
    as   => 'attr',
    code => \&testattr,
  });

  return;
}

my $TEST_CLASS_META = Moose::Meta::Class->create_anon_class(
  superclasses => [ 'Test::Routine::Test' ],
  cache        => 1,
  roles        => [ 'JMAP::TestSuite::TestRoutine::JMAPTest' ],
);

my %attr;

sub testattr {
  my ($name, $value) = @_;
  Carp::confess(qq{unknown test attribute "$name"}) unless $name eq 'pristine';
  Carp::confess(qq{test attribute "$name" already set}) if exists $attr{$name};
  $attr{$name} = $value;
}

sub jmaptest (&) {
  my $code = shift;

  my %origin;
  my $package;
  state $i = 0;
  ($package, @origin{qw(file line nth)}) = (caller, $i++);

  Moose::Util::apply_all_roles($package, 'Test::Routine::Common');

  my $method = $TEST_CLASS_META->name->wrap(
    name => "test from $origin{file}",
    body => $code,
    package_name => $package,
    _origin      => \%origin,
  );

  my $meta = Moose::Meta::Class->initialize($package);

  $meta->add_method($method->name, $method);

  my $builder = Test::Routine::Compositor->instance_builder($package);

  my $instance = $builder->();

  if ($attr{pristine}) {
    unless ($instance->server->can('pristine_account')) {
      Test::More::plan skip_all =>
        "test requires implementation of pristine_account";
      exit;
    }
  }

  my $runner = Test::Routine::Runner->new({
    description   => "tests",
    instance_from => sub { $instance },
  });

  $runner->run;

  Test::More::done_testing;
}

1;
