use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mailbox1 = $account->create_mailbox;

  my $state = $account->get_state('mailbox');

  my $mailbox2 = $account->create_mailbox;

  subtest "good ref" => sub {
    # Should only see mailbox2
    my $res = $tester->request({
      methodCalls => [
        [
          "Mailbox/changes" => {
            sinceState => $state,
          }, "t0",
        ], [
          "Mailbox/get" => {
            "#ids" => {
              resultOf => "t0",
              name     => "Mailbox/changes",
              path     => "/created",
            },
          }, "t1",
        ],
      ],
    });

    my $changes = $res->sentence(0);
    my $get = $res->sentence(1);

    jcmp_deeply(
      $changes->arguments,
      superhashof({
        created => [ $mailbox2->id ],
      }),
      'Mailbox/changes looks good',
    ) or diag explain $res->as_stripped_triples;

    jcmp_deeply(
      $get->arguments,
      superhashof({
        list => [
          superhashof({
            id   => $mailbox2->id,
            name => $mailbox2->name,
          }),
        ],
        notFound => [],
      }),
      'Mailbox/get with backref looks good'
    );
  };

  subtest "bad ref -> resultReference error" => sub {
    for my $test (
      { resultOf => "bad", name => "Mailbox/changes", path => "/created" },
      { resultOf => "t0",  name => "bad",             path => "/created" },
      { resultOf => "t0",  name => "Mailbox/changes", path => "bad"      },
    ) {
      # Should only see mailbox2
      my $res = $tester->request({
        methodCalls => [
          [
            "Mailbox/changes" => {
              sinceState => $state,
            }, "t0",
          ], [
            "Mailbox/get" => {
              "#ids" => $test,
            }, "t1"
          ],
        ],
      });

      my $changes = $res->sentence(0);
      my $get = $res->sentence(1);

      jcmp_deeply(
        $changes->arguments,
        superhashof({
          created => [ $mailbox2->id ],
        }),
        'Mailbox/changes looks good',
      );

      jcmp_deeply(
        $get->arguments,
        superhashof({
          type => 'invalidResultReference',
        }),
        'Mailbox/get with bad backref gets error'
      );
    }
  };

  subtest "#foo and foo -> invalidArguments" => sub {
    # Should only see mailbox2
    my $res = $tester->request({
      methodCalls => [
        [
          "Mailbox/changes" => {
            sinceState => $state,
          }, "t0",
        ], [
          "Mailbox/get" => {
            ids => [ $mailbox1->id ],
            "#ids" => {
              resultOf => "t0",
              name     => "Mailbox/changes",
              path     => "/created",
            },
          }, "t1",
        ],
      ],
    });

    my $changes = $res->sentence(0);
    my $get = $res->sentence(1);

    jcmp_deeply(
      $changes->arguments,
      superhashof({
        created => [ $mailbox2->id ],
      }),
      'Mailbox/changes looks good',
    );

    jcmp_deeply(
      $get->arguments,
      superhashof({
        type => 'invalidArguments',
      }),
      'Mailbox/get with backref and arg sharing name fails'
    ) or diag explain $res->as_stripped_triples;
  };
};
