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

  my $blob = $context->email_blob(generic => {});
  ok($blob->is_success, "our upload succeeded (" . $blob->blobId . ")");

  $batch = $context->import_messages({
    msg => { blobId => $blob, mailboxIds => [ $x->id ] },
  });

  batch_ok($batch);

  ok($batch->is_entirely_successful, "we uploaded and imported messages");

  subtest "getMessages" => sub {
    my $res = $tester->request([
      [
        getMessages => {
          ids => [ $batch->result_for('msg')->id ],
          properties => [ qw(body preview) ],
        }
      ],
    ]);

    my $email = $res->single_sentence->arguments->{list}[0];

    is(
      $email->{textBody},
      'This is a very simple message.',
      'textBody is correct'
    );

    my $preview = substr $email->{textBody}, 0, 5;

    like(
      $email->{preview},
      qr/^$preview/i,
      'preview looks good'
    );
  };

  subtest "getMessageList" => sub {
    my $res = $tester->request([
      [
        getMessageList => {
          filter => { inMailbox => $x->id },
          fetchMessages => \1,
          fetchMessagesProperties => [ qw(body preview) ],
        }
      ],
    ]);

    my $email = $res->sentence(1)->arguments->{list}[0];

    is(
      $email->{textBody},
      'This is a very simple message.',
      'textBody is correct'
    );

    my $preview = substr $email->{textBody}, 0, 5;

    like(
      $email->{preview},
      qr/^$preview/i,
      'preview looks good'
    );
  };
});

done_testing;
