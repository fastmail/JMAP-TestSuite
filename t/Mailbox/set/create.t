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

pristine_test "Mailbox/set create with defaults omitted" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $new_name = guid_string();

  my $res = $tester->request({
    using => [ "ietf:jmapmail" ],
    methodCalls => [[
      "Mailbox/set" => {
        create => {
          new => {
            name => $new_name, # only one without a default
          },
        },
      },
    ]],
  });
  ok($res->is_success, "Mailbox/set create")
    or diag explain $res->http_response->as_string;

  # Not checking oldState here as server may not have one yet
  jcmp_deeply(
    $res->single_sentence("Mailbox/set")->arguments,
    superhashof({
      accountId => jstr($self->context->accountId),
      newState  => jstr(),
    }),
    "Set response looks good",
  );

  my $created =
    $res->single_sentence("Mailbox/set")->arguments->{created}{new};

  ok($created, 'created a new mailbox');

  my $id = $res->single_sentence("Mailbox/set")->as_set->created_id('new');
  ok($id, 'got a new id');

  # Server does not have to return fields, but does need to return id
  jcmp_deeply(
    $created,
    superhashof({
      id => jstr(),
    }),
    "Our mailbox looks good"
  ) or diag explain $res->as_stripped_triples;

  subtest "Confirm our name/defaults good" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/get" => {
          ids => [ $id ],
        },
      ]],
    });
    ok($res->is_success, "Mailbox/get")
      or diag explain $res->http_response->as_string;

    my @found = @{ $res->single_sentence("Mailbox/get")->arguments->{list} };
    is(@found, 1, 'got only 1 mailbox');

    jcmp_deeply(
      $found[0],
      superhashof({
        id           => jstr($id),
        name         => jstr($new_name),
        parentId     => undef, # XXX - Maybe decided by server
        role         => undef,
        sortOrder    => jnum(0),
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
      "Our mailbox looks good",
    );
  };
};

pristine_test "Mailbox/set create with all settable fields provided" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $new_name = guid_string();

  my $parent = $self->context->create_mailbox;

  # We should have state after creating a parent mailbox
  my $state = $self->context->get_state('mailbox');

  # XXX - Create with role test -- alh, 2018-02-22

  my $res = $tester->request({
    using => [ "ietf:jmapmail" ],
    methodCalls => [[
      "Mailbox/set" => {
        create => {
          new => {
            name      => $new_name,
            parentId  => $parent->id,
            sortOrder => 55,
          },
        },
      },
    ]],
  });
  ok($res->is_success, "Mailbox/set create")
    or diag explain $res->http_response->as_string;

  jcmp_deeply(
    $res->single_sentence("Mailbox/set")->arguments,
    superhashof({
      accountId => jstr($self->context->accountId),
      newState  => jstr(),
      oldState  => jstr($state),
    }),
    "Set response looks good",
  );

  my $created =
    $res->single_sentence("Mailbox/set")->arguments->{created}{new};

  ok($created, 'created a new mailbox');

  my $id = $res->single_sentence("Mailbox/set")->as_set->created_id('new');
  ok($id, 'got a new id');

  # Server does not have to return fields, but does need to return id
  jcmp_deeply(
    $created,
    superhashof({
      id           => jstr(),
    }),
    "Our mailbox looks good"
  ) or diag explain $res->as_stripped_triples;

  subtest "Confirm our name is good" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/get" => {
          ids => [ $id ],
          properties => [ 'name', 'parentId', 'sortOrder' ],
        },
      ]],
    });
    ok($res->is_success, "Mailbox/get")
      or diag explain $res->http_response->as_string;

    my @found = @{ $res->single_sentence("Mailbox/get")->arguments->{list} };
    is(@found, 1, 'got only 1 mailbox');

    jcmp_deeply(
      $found[0],
      superhashof({
        id        => jstr($id),
        name      => jstr($new_name),
        parentId  => jstr($parent->id),
        sortOrder => jnum(55),
      }),
      "Our mailbox settings looks good"
    ) or diag explain $res->as_stripped_triples;
  };
};

test "Setting with immutable fields" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  # First, figure out our defaults. See if they are consistent across
  # at least two creates
  my $mailbox1 = $self->context->create_mailbox;
  my $mailbox2 = $self->context->create_mailbox;

  my @immutable = qw(
    totalEmails
    unreadEmails
    totalThreads
    unreadThreads
  );

  my @immutable_rights = qw(
    mayReadItems
    mayAddItems
    mayRemoveItems
    maySetSeen
    maySetKeywords
    mayCreateChild
    mayRename
    mayDelete
    maySubmit
  );

  for my $f (@immutable, @immutable_rights) {
    unless ($mailbox1->$f eq $mailbox2->$f) {
      plan skip_all => "$f differed with two fresh mailboxes. Cannot test without predictable values";
    }
  }

  my $get_res = $tester->request({
    using => [ "ietf:jmapmail" ],
    methodCalls => [[
      "Mailbox/get" => { ids => [ $mailbox1->id ] },
    ]],
  });

  my $mb = $get_res->single_sentence('Mailbox/get')->arguments->{list}[0];
  ok($mb, 'got a fresh mailbox');

  delete($mb->{id});

  subtest "immutable properties with correct values is okay" => sub {
    $mb->{name} .= " a change";

    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/set" => {
          create => {
            new => $mb,
          },
        },
      ]],
    });

    ok($res->is_success, "Mailbox/set create")
      or diag explain $res->http_response->as_string;

    ok(
      $res->single_sentence("Mailbox/set")->arguments->{created}{new},
      "created our mailbox passing in immutable params!"
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "immutable properties with wrong values is not okay" => sub {
    $mb->{name} .= " and another";
    $mb->{id} = $mailbox1->id;

    my %rights = map {;
      $_ => $mailbox1->$_ ? JSON::false : JSON::true
    } keys %{ $mailbox1->myRights };

    $mb->{myRights} = \%rights;
    $mb->{$_} = 52 for qw(
      totalEmails
      unrealEmails
      totalThreads
      unreadThreads
    );

    my $set_res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/set" => {
          create => {
            new => $mb,
          },
        },
      ]],
    });

    jcmp_deeply(
      $set_res->single_sentence('Mailbox/set')->arguments->{notCreated}{new},
      {
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
      'got errors for immutable properties'
    ) or diag explain $set_res->as_stripped_triples;
  };
};

run_me;
done_testing;
