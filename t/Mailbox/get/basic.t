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

pristine_test "No entities" => sub {
  my ($self) = @_;

  plan skip_all => "Cyrus requires at least one mailbox"
    if $self->server->isa('JMAP::TestSuite::ServerAdapter::Cyrus');

  my $tester = $self->tester;

  subtest "No arguments" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/get" => {}
      ]],
    });
    ok($res->is_success, "Mailbox/get")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/get")->arguments->{list},
      [],
      "No mailboxes looks good",
    );
  };
};

pristine_test "Some mailboxes" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $mailbox = $self->context->create_mailbox({
    name => "A new mailbox",
  });

  subtest "No arguments" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/get" => {}
      ]],
    });
    ok($res->is_success, "Mailbox/get")
      or diag explain $res->http_response->as_string;

    my @found = grep {;
      $_->{id} eq $mailbox->id
    } @{ $res->single_sentence("Mailbox/get")->arguments->{list} };

    is(@found, 1, 'found our mailbox');

    jcmp_deeply(
      $found[0],
      superhashof({
        id           => jstr($mailbox->id),
        name         => jstr("A new mailbox"),
        parentId     => undef, # XXX - May be decided by server?
        role         => undef,
        sortOrder    => jnum(),
        totalEmails  => jnum(0),
        unreadEmails => jnum(0),
        totalEmails  => jnum(0),
        unreadEmails => jnum(0),
        myRights     => superhashof({
          map {
            $_ => jbool(),
          } qw(
            mayReadItems
            mayAddItems
            mayRemoveItems
            maySetSeen
            maySetKeywords
            mayCreateChild
            mayRename
            mayDelete
            maySubmit
          )
        }),
      }),
      "Our mailbox looks good"
    );

    diag explain $res->as_stripped_triples;
  };
};

run_me;
done_testing;
