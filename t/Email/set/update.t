use strict;
use warnings;
use Test::Routine;
use Test::Routine::Util;

with 'JMAP::TestSuite::Tester';

use JMAP::TestSuite::Util qw(batch_ok pristine_test);

use Test::Deep ':v1';
use Test::Deep::JType;
use Test::More;
use JSON qw(decode_json);
use JSON::Typist;
use Test::Abortable;
use Path::Tiny;
use Digest::MD5 qw(md5_hex);

use utf8;

test "update email keywords" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $mbox = $self->context->create_mailbox;

  my $from    = "test$$\@example.net";
  my $to      = "recip$$\@example.net";
  my $subject = "A subject for $$";

  my $message = $mbox->add_message({
    from    => $from,
    to      => $to,
    subject => $subject,
  });

  $tester->request_ok(
    [ "Email/get" => { ids => [ $message->id ] } ],
    superhashof({ list => [ superhashof({ keywords => {} }) ] }),
    "newly created email has no keywords",
  );

  $tester->request_ok(
    [
      "Email/set" => {
        update => {
          $message->id => { keywords => { '$Flagged' => jtrue() } }
        },
      }
    ],
    superhashof({ updated => { $message->id => ignore } }),
    'we set $flagged keyword',
  );

  $tester->request_ok(
    [ "Email/get" => { ids => [ $message->id ] } ],
    superhashof({ list => [ superhashof({ keywords => { '$flagged' => jtrue() } }) ] }),
    "...and it worked, keyword lowercased",
  );
};

run_me;
done_testing;

