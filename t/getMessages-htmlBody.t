use strict;
use warnings;
use Test::Routine;
use Test::Routine::Util;

with 'JMAP::TestSuite::Tester';

use JMAP::TestSuite::Util qw(batch_ok pristine_test);

use Test::Deep::JType;
use Test::More;
use Test::Abortable;

use DateTime;
use Email::MessageID;

test "getMessages-htmlBody" => sub {
  my ($self) = @_;

  my ($context) = $self->context;

  my $tester = $context->tester;

  # Get us a mailbox to play with
  my $batch = $context->create_batch(mailbox => {
      x => { name => "Folder X at $^T.$$" },
  });

  batch_ok($batch);

  ok( $batch->is_entirely_successful, "created a mailbox");
  my $x = $batch->result_for('x');

  my $blob = $context->email_blob(generic => {});
  ok($blob->is_success, "our upload succeeded (" . $blob->blobId . ")");

  $batch = $context->import_messages({
    msg => { blobId => $blob, mailboxIds => { $x->id => \1 }, },
  });

  batch_ok($batch);

  ok($batch->is_entirely_successful, "we uploaded and imported messages");

  my $res = $tester->request({
    using => ["ietf:jmapmail"],

    methodCalls => [
      [
        'Email/get' => {
          ids => [ $batch->result_for('msg')->id ],
        }
      ],
    ],
  });

  is(
    $res->single_sentence->arguments->{list}[0]{textBody},
    'This is a very simple message.',
    'textBody is correct'
  );

  isnt(
    $res->single_sentence->arguments->{list}[0]{htmlBody},
    'This is a very simple message.',
    'htmlBody is correct'
  );
};

run_me;
done_testing;
