use jmaptest;

use Data::GUID qw(guid_string);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $new_name = guid_string();

  my $res = $tester->request([[
    "Mailbox/set" => {
      create => {
        new => {
          name => $new_name, # only one without a default
        },
      },
    },
  ]]);
  ok($res->is_success, "Mailbox/set create")
    or diag explain $res->response_payload;

  # Not checking oldState here as server may not have one yet
  jcmp_deeply(
    $res->single_sentence("Mailbox/set")->arguments,
    superhashof({
      accountId => jstr($account->accountId),
      newState  => jstr(),
    }),
    "Set response looks good",
  );

  my $created =
    $res->single_sentence("Mailbox/set")->arguments->{created}{new};

  ok($created, 'created a new mailbox');

  my $id = $res->single_sentence("Mailbox/set")->as_set->created_id('new');
  ok($id, 'got a new id');

  # RFC 8620 S5.3: created holds "all server-set properties" and any
  # "omitted by the client and thus set to a default by the server".
  jcmp_deeply(
    $created,
    superhashof({
      id            => jstr(),
      parentId      => any(jstr, undef),
      role          => any(jstr, undef),
      sortOrder     => jnum,
      isSubscribed  => jbool,
      totalEmails   => jnum(0),
      unreadEmails  => jnum(0),
      totalThreads  => jnum(0),
      unreadThreads => jnum(0),
      myRights      => superhashof({
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
  ) or diag explain $res->as_stripped_triples;

  subtest "Confirm our name/defaults good" => sub {
    my $res = $tester->request({
      methodCalls => [[
        "Mailbox/get" => {
          ids => [ $id ],
        },
      ]],
    });
    ok($res->is_success, "Mailbox/get")
      or diag explain $res->response_payload;

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
        totalEmails   => jnum(0),
        unreadEmails  => jnum(0),
        totalThreads  => jnum(0),
        unreadThreads => jnum(0),
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
