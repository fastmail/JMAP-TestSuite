use strict;
use warnings;
use Test::Routine;
use Test::Routine::Util;

with 'JMAP::TestSuite::Tester';

use JMAP::TestSuite::Util qw(batch_ok pristine_test);

use Test::Deep::JType;
use Test::More;
use Test::Abortable;

test "basic" => sub {
  my ($self) = @_;

  my $context = $self->context;

  my $tester = $context->tester;
  my $res = $tester->request([[ "Mailbox/get" => {} ]]);
  my $pairs = $res->as_triples;

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

    ok($blob->is_success, "our upload succeeded (" . $blob->blobId . ")");

    my $batch = $context->import_messages({
      msg => { blobId => $blob, mailboxIds => { $role{inbox}{id} => \1 }, },
    });

    batch_ok($batch);

    ok($batch->is_entirely_successful, "we uploaded");
  }
};

run_me;
done_testing;
