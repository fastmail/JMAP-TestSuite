use strict;
use warnings;
package JMAP::TestSuite::Util;

use Sub::Exporter -setup => [ qw(batch_ok) ];

use Test::Deep::JType;
use Test::More;

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

  {
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

1;
