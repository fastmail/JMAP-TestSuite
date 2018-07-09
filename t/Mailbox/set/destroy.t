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

test "Mailbox/set good destroy, no messages" => sub {
  my ($self) = @_;

  my $tester = $self->tester;
  my $context = $self->context;

  my $mailbox1 = $self->context->create_mailbox;

  my $set_res = $tester->request({
    using => [ "ietf:jmapmail" ],
    methodCalls => [[
      "Mailbox/set" => {
        destroy => [ $mailbox1->id ],
      },
    ]],
  });

  jcmp_deeply(
    $set_res->single_sentence('Mailbox/set')->arguments->{destroyed},
    [ $mailbox1->id ],
    'mailbox destroyed'
  );

  my $get_res = $tester->request({
    using => [ "ietf:jmapmail" ],
    methodCalls => [[
      "Mailbox/get" => { ids => [ $mailbox1->id ] },
    ]],
  });

  jcmp_deeply(
    $get_res->single_sentence('Mailbox/get')->arguments->{list},
    [],
    'no mailboxes returned'
  );

  jcmp_deeply(
    $get_res->single_sentence('Mailbox/get')->arguments->{notFound},
    [ $mailbox1->id ],
    'our destroyed mailbox not found'
  );
};

test "mailboxHasEmail error" => sub {
  my ($self) = @_;

  my $tester = $self->tester;
  my $context = $self->context;

  for my $test (
    [ 'implicit onDestroyRemoveMessages false' => {} ],
    [ 'explicit onDestroyRemoveMessages false' => {
        onDestroyRemoveMessages => JSON::false,
      },
    ],
  ) {
    my ($desc, $arg) = @$test;

    subtest "has message - $desc" => sub {
      my $mailbox1 = $self->context->create_mailbox;

      my $message = $mailbox1->add_message;

      my $set_res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Mailbox/set" => {
            destroy => [ $mailbox1->id ],
            %$arg,
          },
        ]],
      });

      jcmp_deeply(
        $set_res->single_sentence('Mailbox/set')->arguments->{notDestroyed},
        {
          $mailbox1->id => {
            type => 'mailboxHasEmail',
          },
        },
        'got mailboxHasEmail error'
      );

      my $get_res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Mailbox/get" => { ids => [ $mailbox1->id ] },
        ]],
      });

      jcmp_deeply(
        $get_res->single_sentence('Mailbox/get')->arguments->{list},
        [superhashof({
          id => $mailbox1->id,
        })],
        'mailbox still exists'
      );

      my $email_res = $tester->request({
        using => ["ietf:jmapmail"],
        methodCalls => [[
          "Email/get" => { ids => [ $message->id ], },
        ]],
      });

      my $email = $email_res->single_sentence->arguments->{list}[0];
      ok($email, 'our message still exists');
    };
  }
};

test "has message - onDestroyRemoveMessages true, mail only here" => sub {
  my ($self) = @_;

  my $tester = $self->tester;
  my $context = $self->context;

  my $mailbox1 = $self->context->create_mailbox;

  my $blob = $context->email_blob(generic => {});
  ok($blob->is_success, "our upload succeeded (" . $blob->blobId . ")");

  my $message = $mailbox1->add_message;

  my $set_res = $tester->request({
    using => [ "ietf:jmapmail" ],
    methodCalls => [[
      "Mailbox/set" => {
        destroy => [ $mailbox1->id ],
        onDestroyRemoveMessages => JSON::true,
      },
    ]],
  });

  jcmp_deeply(
    $set_res->single_sentence('Mailbox/set')->arguments->{destroyed},
    [ $mailbox1->id ],
    'mailbox destroyed'
  );

  my $get_res = $tester->request({
    using => [ "ietf:jmapmail" ],
    methodCalls => [[
      "Mailbox/get" => { ids => [ $mailbox1->id ] },
    ]],
  });

  jcmp_deeply(
    $get_res->single_sentence('Mailbox/get')->arguments->{notFound},
    [ $mailbox1->id ],
    'our destroyed mailbox not found'
  );

  my $email_res = $tester->request({
    using => ["ietf:jmapmail"],
    methodCalls => [[
      "Email/get" => { ids => [ $message->id ], },
    ]],
  });

  jcmp_deeply(
    $email_res->single_sentence('Email/get')->arguments->{notFound},
    [ $message->id ],
    'our destroyed email not found'
  );
};

test "has message - onDestroyRemoveMessages true, mail in other boxes" => sub {
  my ($self) = @_;

  my $tester = $self->tester;
  my $context = $self->context;

  # Put our message in two boxes. It should be removed from the first when
  # we destroy the mailbox but exist in the second.
  my $mailbox1 = $self->context->create_mailbox;
  my $mailbox2 = $self->context->create_mailbox;

  my $blob = $context->email_blob(generic => {});
  ok($blob->is_success, "our upload succeeded (" . $blob->blobId . ")");

  my $message = $context->add_message_to_mailboxes(
    $mailbox1->id, $mailbox2->id,
  );

  my $set_res = $tester->request({
    using => [ "ietf:jmapmail" ],
    methodCalls => [[
      "Mailbox/set" => {
        destroy => [ $mailbox1->id ],
        onDestroyRemoveMessages => JSON::true,
      },
    ]],
  });

  jcmp_deeply(
    $set_res->single_sentence('Mailbox/set')->arguments->{destroyed},
    [ $mailbox1->id ],
    'mailbox destroyed'
  );

  my $get_res = $tester->request({
    using => [ "ietf:jmapmail" ],
    methodCalls => [[
      "Mailbox/get" => { ids => [ $mailbox1->id ] },
    ]],
  });

  jcmp_deeply(
    $get_res->single_sentence('Mailbox/get')->arguments->{notFound},
    [ $mailbox1->id ],
    'our destroyed mailbox not found'
  );

  my $email_res = $tester->request({
    using => ["ietf:jmapmail"],
    methodCalls => [[
      "Email/get" => { ids => [ $message->id ], },
    ]],
  });

  my $email = $email_res->single_sentence->arguments->{list}[0];
  ok($email, 'our message still exists');

  jcmp_deeply(
    $email->{mailboxIds},
    { $mailbox2->id => JSON::true },
    'message still exists in second mailbox'
  );
};

test "mailboxHasChild error" => sub {
  my ($self) = @_;

  my $tester = $self->tester;
  my $context = $self->context;

  my $mailbox1 = $self->context->create_mailbox;
  my $mailbox2 = $self->context->create_mailbox({
    parentId => $mailbox1->id,
  });

  subtest "has child" => sub {
    my $set_res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/set" => {
          destroy => [ $mailbox1->id ],
          onDestroyRemoveMessages => JSON::true,
        },
      ]],
    });

    jcmp_deeply(
      $set_res->single_sentence('Mailbox/set')->arguments->{notDestroyed},
      {
        $mailbox1->id => {
          type => 'mailboxHasChild',
        },
      },
      'got mailboxHasChild error'
    );
  };

  subtest "no longer has child" => sub {
    $mailbox2->destroy;

    my $set_res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/set" => {
          destroy => [ $mailbox1->id ],
          onDestroyRemoveMessages => JSON::true,
        },
      ]],
    });

    jcmp_deeply(
      $set_res->single_sentence('Mailbox/set')->arguments->{destroyed},
      [ $mailbox1->id ],
      'mailbox destroyed'
    );

    my $get_res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/get" => { ids => [ $mailbox1->id ] },
      ]],
    });

    jcmp_deeply(
      $get_res->single_sentence('Mailbox/get')->arguments->{list},
      [],
      'no mailboxes returned'
    );

    jcmp_deeply(
      $get_res->single_sentence('Mailbox/get')->arguments->{notFound},
      [ $mailbox1->id ],
      'our destroyed mailbox not found'
    );
  };
};

run_me;
done_testing;
