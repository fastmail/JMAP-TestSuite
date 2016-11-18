use strict;
use warnings;

use JMAP::TestSuite;

use Test::Deep::JType;
use Test::More;

my $server = JMAP::TestSuite->get_server;

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
    require Email::MIME;
    my $email = Email::MIME->create(
      header_str => [
        From => 'example@example.com',
        To   => 'example@example.biz',
        Subject => 'This is a test',
        'Message-Id' => "<$$.$^T\@$$.example.com>",
      ],
      body => "This is a very simple message.",
    );

    my $batch = $context->import_messages({
      msg => { blobId => $email, mailboxIds => [ $role{inbox}{id} ] },
    });

    ok($batch->is_entirely_successful, "we uploaded");
  }
});

done_testing;
