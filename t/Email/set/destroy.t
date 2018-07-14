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

test "delete mail from mailboxes" => sub {
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
    [
      "Email/get" => {
        ids        => [ $message->id ],
        properties => [ 'mailboxIds' ],
      },
    ],
    superhashof({
      list => [
        { id => $message->id, mailboxIds => { $mbox->id => jtrue } },
      ],
    }),
    "we made a message and it's in a mailbox",
  );

  $tester->request_ok(
    [ 'Mailbox/get', { ids => [ $mbox->id ] } ],
    superhashof({ list => [ superhashof({ totalEmails => 1, id => $mbox->id }) ] }),
    "totalEmails count is now 1",
  );

  $tester->request_ok(
    [ 'Email/set', { destroy => [ $message->id ] } ],
    superhashof({ destroyed => [ $message->id ] }),
    "we destroyed an email",
  );

  $tester->request_ok(
    [ 'Mailbox/get', { ids => [ $mbox->id ] } ],
    superhashof({ list => [ superhashof({ totalEmails => 0, id => $mbox->id }) ] }),
    "totalEmails count is now 0",
  );
};

run_me;
done_testing;

