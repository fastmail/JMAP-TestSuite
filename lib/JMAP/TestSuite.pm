package JMAP::TestSuite;
use strict;
use warnings;

use Carp ();
use JSON ();
use Module::Runtime qw(require_module);
use Path::Tiny;

use JMAP::TestSuite::Entity::Mailbox;
use JMAP::TestSuite::Entity::Email;
use JMAP::TestSuite::Entity::Thread;

sub get_server {
  my $fn = $ENV{JMAP_SERVER_ADAPTER_FILE};

  Carp::confess("JMAP_SERVER_ADAPTER_FILE not set")
    unless defined $fn;

  Carp::confess("JMAP_SERVER_ADAPTER_FILE not a readable file")
    unless -r -f $fn;

  my $json = path($fn)->slurp_utf8;

  my $data = JSON->new->decode($json);

  Carp::confess("JMAP server does not provide adapter")
    unless my $adapter_class = delete $data->{adapter};

  $adapter_class = "JMAP::TestSuite::ServerAdapter::$adapter_class"
    unless $adapter_class =~ s/^=//;

  require_module($adapter_class);

  return $adapter_class->new($data);
}

1;
