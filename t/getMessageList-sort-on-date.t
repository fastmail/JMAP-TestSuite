use strict;
use warnings;

use JMAP::TestSuite;
use JMAP::TestSuite::Util qw(batch_ok);

use Test::Deep::JType;
use Test::More;

use DateTime;
use Email::MessageID;

my $server = JMAP::TestSuite->get_server;

$server->simple_test(sub {
  my ($context) = @_;

  my $tester = $context->tester;

  # Get us a mailbox to play with
  my $batch = $context->create_batch(mailbox => {
      x => { name => "Folder X at $^T.$$" },
  });

  batch_ok($batch);

  ok( $batch->is_entirely_successful, "created a mailbox");
  my $x = $batch->result_for('x');

  my %message = (
    2016 => {
      header => "Sun, 25 Dec 2016 12:00:01 −0300",
      date   => '2016-12-25T12:00:01Z',
    },
    2005 => {
      header => "Sun, 25 Dec 2005 12:00:01 −0300",
      date   => '2005-12-25T12:00:01Z',
    },
  );

  # Import messages with specific dates, expect
  # the highest to come back when sorting by date desc
  for my $year (sort { $b <=> $a } keys %message) {
    my ($hdr_date, $date) = $message{$year}->@{ qw(header date) };
    subtest "message with date header $hdr_date" => sub {
      my $blob = $context->email_blob(generic => {
        message_id => Email::MessageID->new->in_brackets,
        date       => $hdr_date,
      });

      ok($blob->is_success, "our upload succeeded (" . $blob->blobId . ")");

      $batch = $context->import_messages({
        msg => { blobId => $blob, mailboxIds => [ $x->id ] },
      });

      batch_ok($batch);

      ok($batch->is_entirely_successful, "we uploaded and imported messages");

      my $message_id = $batch->result_for('msg')->id;
      $message{$year}{id} = $message_id;
    };
  }

  my $res = $tester->request([
    [
      getMessageList => {
        filter => { inMailbox   => $x->id },
        sort                    => [ 'date desc' ],
        limit                   => 1,
        fetchMessages           => jtrue(),
        fetchMessageProperties  => [ 'date', ] ,
      }
    ],
  ]);

  my $first   = $res->sentence(1)->arguments->{list}[0];
  my ($which) = grep { $message{$_}{id} eq $first->{id} } keys %message;

  is($which, 2005, "the more recently imported message is newer");

  isnt(
    $first->{date},
    $message{$which}{date},
    "the message.date is not from the ancient header value"
  );

  cmp_ok(
    $first->{date}, 'gt', '2017-01-01',
    "...and we return an internaldate in the plausible present"
  );
});

done_testing;
