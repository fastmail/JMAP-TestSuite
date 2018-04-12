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
use Data::GUID qw(guid_string);
use Test::Abortable;

# XXX - Test for setting role

test "Mailbox/set update" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $mailbox1 = $self->context->create_mailbox;
  my $mailbox2 = $self->context->create_mailbox;

  subtest "change mutable fields" => sub {
    my $set_res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/set" => {
          update => {
            $mailbox2->id => {
              name      => "New Name",
              parentId  => $mailbox1->id,
              sortOrder => 53,
            },
          },
        },
      ]],
    });

    jcmp_deeply(
      $set_res->single_sentence('Mailbox/set')->arguments->{updated},
      { $mailbox2->id => ignore() },
      'mailbox updated'
    );

    my $get_res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/get" => { ids => [ $mailbox2->id ] },
      ]],
    });

    jcmp_deeply(
      $get_res->single_sentence('Mailbox/get')->arguments->{list},
      [superhashof({
        name      => "New Name",
        parentId  => $mailbox1->id,
        sortOrder => 53,
      })],
      'mailbox updated'
    );
  };

  subtest "can hand in immutable fields if they are same" => sub {
    my $get_res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/get" => { ids => [ $mailbox2->id ] },
      ]],
    });

    my $mb = $get_res->single_sentence('Mailbox/get')->arguments->{list}[0];
    ok($mb, 'got our mailbox');

    $mb->{name} = "A Newer Name";

    my $set_res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/set" => {
          update => {
            $mailbox2->id => $mb,
          },
        },
      ]],
    });

    jcmp_deeply(
      $set_res->single_sentence('Mailbox/set')->arguments->{updated},
      { $mailbox2->id => ignore() },
      'mailbox updated'
    );

    my $re_get_res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/get" => { ids => [ $mailbox2->id ] },
      ]],
    });

    jcmp_deeply(
      $re_get_res->single_sentence('Mailbox/get')->arguments->{list},
      [superhashof({
        name      => "A Newer Name",
        parentId  => $mailbox1->id,
        sortOrder => 53,
      })],
      'mailbox updated'
    );
  };

  subtest "cannot change immutable fields" => sub {
    # Flop all the values
    my %rights = map {;
      $_ => $mailbox2->$_ ? JSON::false : JSON::true
    } keys %{ $mailbox2->myRights };

    my $set_res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/set" => {
          update => {
            $mailbox2->id => {
              id            => $mailbox2->id . "a",
              totalEmails   => 52,
              unreadEmails  => 52,
              totalThreads  => 52,
              unreadThreads => 52,
              myRights => \%rights,
            },
          },
        },
      ]],
    });

    jcmp_deeply(
      $set_res->single_sentence('Mailbox/set')->arguments->{notUpdated},
      {
        $mailbox2->id => {
          type => 'invalidProperties',
          properties => set(
            qw(
              id
              totalEmails
              unreadEmails
              totalThreads
              unreadThreads
            ),
            map {; "myRights/$_" } keys %rights,
          ),
        },
      },
      'got errors for immutable properties'
    ) or diag explain $set_res->as_stripped_triples;
  };
};

run_me;
done_testing;
