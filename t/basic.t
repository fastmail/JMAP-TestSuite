use strict;
use warnings;

use JMAP::TestSuite;

use Test::Deep::JType;
use Test::More;

my $server = JMAP::TestSuite->get_server;

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
        diag("  $_ has unknown properties: "
            . join(q{, }, $batch->result_for($_)->unknown_properties)
        );
      }
    } else {
      pass("no unknown properties in batch results");
    }
  }
}

$server->simple_test(sub {
  my ($context) = @_;

  my $tester = $context->tester;
  my $res = $tester->request([[ getMailboxes => {} ]]);

  my $pairs = $res->as_pairs;

  is(@$pairs, 1, "one sentence of response to getMailboxes");

  my @mailboxes = @{ $pairs->[0][1]{list} };

  my %role;
  for my $mailbox (grep {; defined $_->{role} } @mailboxes) {
    if ($role{ $mailbox->{role} }) {
      fail("role $mailbox->{role} appears multiple times");
    }

    $role{ $mailbox->{role} } = $mailbox;
  }

  {
    my $batch = $context->create_batch(mailbox => {
      x => { name => "Folder X at $^T.$$" },
      y => { name => undef },
      z => { name => "Folder Z", parentId => '#x' },
    });

    batch_ok($batch);

    ok( ! $batch->is_entirely_successful, "something failed");
    ok(  $batch->result_for('y')->is_error, 'y failed');
    my $x = ok(! $batch->result_for('x')->is_error, 'x succeeded');
    my $z = ok(! $batch->result_for('z')->is_error, 'z succeeded');

    if ($x && $z) {
      is(
        $batch->result_for('z')->parentId,
        $batch->result_for('x')->id,
        "z.parentId == x.id",
      );
    }
  }

  {
    my $blob = $context->email_blob(generic => {
      message_id => "<$$.$^T\@$$.example.com>",
    });

    my $batch = $context->import_messages({
      msg => { blobId => $blob, mailboxIds => [ $role{inbox}{id} ] },
    });

    batch_ok($batch);

    ok($batch->is_entirely_successful, "we uploaded");
  }
});

done_testing;
