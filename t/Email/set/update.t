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
 
  my @setters = (
    {
      desc  => "bulk set",
      data  => { keywords => { '$Flagged' => jtrue } },
    },
    {
      desc  => "patch set",
      data  => { 'keywords/$Flagged' => jtrue },
    },
    {
      desc  => "patch set integer",
      data  => { 'keywords/$Flagged' => 1 },
      fail  => 1,
    },
  );

  my @clearers = (
    {
      desc  => "bulk clear",
      data => { keywords => { } },
    },
    {
      desc  => "patch set null",
      data  => { 'keywords/$Flagged' => undef },
    },
    {
      desc  => "patch set false",
      data  => { 'keywords/$Flagged' => jfalse },
      set_fail => 1,
    },
  );
  
  SETTER: for my $setter (@setters) {
    GETTER: for my $clearer (@clearers) {
      subtest "setter($setter->{desc}) clearer($clearer->{desc})" => sub {
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
          [ "Email/set" => { update => { $message->id => $setter->{data} } } ],
          ($setter->{fail}
            ? superhashof({ notUpdated => { $message->id => ignore } })
            : superhashof({ updated    => { $message->id => ignore } })),
          'tried to set $flagged keyword: should ' . ($setter->{fail} ? 'fail' : 'work')
        );

        return if $setter->{fail};

        $tester->request_ok(
          [ "Email/get" => { ids => [ $message->id ] } ],
          superhashof({ list => [ superhashof({ keywords => { '$flagged' => jtrue() } }) ] }),
          '...and it worked, keyword $flagged set',
        );

        $tester->request_ok(
          [ "Email/set" => { update => { $message->id => $clearer->{data} } } ],
          ($clearer->{fail}
            ? superhashof({ notUpdated => { $message->id => ignore } })
            : superhashof({ updated    => { $message->id => ignore } })),
          'tried to clear $flagged keyword: should ' . ($clearer->{fail} ? 'fail' : 'work')
        );

        return if $clearer->{fail};

        $tester->request_ok(
          [ "Email/get" => { ids => [ $message->id ] } ],
          superhashof({ list => [ superhashof({ keywords => { } }) ] }),
          "...and it worked, keyword removed",
        );
      };

      next SETTER if $setter->{fail};
    }
  }
};

run_me;
done_testing;

