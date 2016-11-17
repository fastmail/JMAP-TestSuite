use strict;
use warnings;

use JMAP::TestSuite::ServerAdapter::JMAPProxy;
use JMAP::TestSuite::Entity::Mailbox;
use JMAP::TestSuite::Entity::Message;

use Test::Deep::JType;
use Test::More;

my $ti = JMAP::TestSuite::ServerAdapter::JMAPProxy->new({
  accountIds => [ 'b0b7699c-4474-11e6-b790-f23c91556942' ],
  base_uri    => q{http://localhost:9000/},
});

$ti->simple_test(sub {
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
    });

    ok( ! $batch->is_entirely_successful, "something failed");
    ok(! $batch->result_for('x')->is_error, 'x succeeded');
    ok(  $batch->result_for('y')->is_error, 'y failed');
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
