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

  my $msg_id = Email::MessageID->new->in_brackets;
  my $blob = $context->email_blob(generic => { message_id => $msg_id });
  ok($blob->is_success, "our upload succeeded (" . $blob->blobId . ")");

  $batch = $context->import_messages({
    msg => { blobId => $blob, mailboxIds => [ $x->id ] },
  });

  batch_ok($batch);

  ok($batch->is_entirely_successful, "we uploaded and imported messages");

  for my $test (
    [ "getting message-id as a default header property" => {} ],
    [ "requesting header.message-id explicitly" => { properties => [ 'header.message-id' ] } ],
  ) {
    my ($desc, $extra) = @$test;

    subtest $desc => sub {
      my $res = $tester->request([
        [
          getMessages => {
            ids => [ $batch->result_for('msg')->id ],
            %$extra,
          }
        ],
      ]);

      my $prop = $res->single_sentence('messages')->arguments->{list}[0];
      my %header = %{ $prop->{headers} || {} };

      my (@any_case) = grep {; 'message-id' eq lc $_ } keys %header;
      ok(@any_case, "message-id appears in headers in any case");

      my $lc = grep {; 'message-id' eq $_ } keys %header;
      ok($lc, "message-id appears in headers exactly");

      if (@any_case and not $lc) {
        diag "message-id appeared in these forms: @any_case";
      }

      for (@any_case) {
        is($header{$_}, $msg_id, "header $_ is the message id");
      }
    };
  }
});

done_testing;
