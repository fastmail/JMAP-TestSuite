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
use JSON;

test "previews" => sub {
  my ($self) = @_;

  my $context = $self->context;

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

  subtest "getMessages" => sub {
    my $res = $tester->request({
      using => ["ietf:jmapmail"],

      methodCalls => [
        [
          'Email/get' => {
            ids => [ $batch->result_for('msg')->id ],
            properties => [ qw(preview bodyValues textBody) ],
            fetchTextBodyValues => JSON::true,
          },
        ],
      ],
    });

    my $email = $res->single_sentence->arguments->{list}[0];

    my $text_id = $email->{textBody}[0]{partId};
    my $text_body = $email->{bodyValues}{$text_id}{value};

    is(
      $text_body,
      'This is a very simple message.',
      'text body is correct'
    ) or diag explain $email;

    my $preview = substr $text_body, 0, 5;

    like(
      $email->{preview},
      qr/^$preview/i,
      'preview looks good'
    );
  };

  subtest "getMessageList" => sub {
    my $res = $tester->request({
      using => ["ietf:jmapmail"],

      methodCalls => [
        [
          'Email/query' => {
            filter => { inMailbox => $x->id },
          }, 'query',
        ],
        [
          'Email/get' => {
            '#ids' => {
              resultOf => 'query',
              name     => 'Email/query',
              path     => '/ids',
            },
            properties => [ qw(preview bodyValues textBody) ],
            fetchTextBodyValues => JSON::true,
          },
        ],
      ],
    });

    my $email = $res->sentence(1)->arguments->{list}[0];

    my $text_id = $email->{textBody}[0]{partId};
    my $text_body = $email->{bodyValues}{$text_id}{value};

    is(
      $text_body,
      'This is a very simple message.',
      'text body is correct'
    );

    my $preview = substr $text_body, 0, 5;

    like(
      $email->{preview},
      qr/^$preview/i,
      'preview looks good'
    );
  };
};

run_me;
done_testing;
