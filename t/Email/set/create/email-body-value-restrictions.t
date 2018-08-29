use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;

  # isTruncated / isEncodingProblem must be false or omitted

  subtest "omitted" => sub {
    $tester->request_ok(
      [
        "Email/set" => {
          create => {
            new => {
              mailboxIds => { $mbox->id => \1, },
              bodyStructure => {
                partId => 'text',
                type   => 'text/plain',
              },
              bodyValues => {
                text => {
                  value => 'email',
                },
              },
            },
          },
        },
      ],
      superhashof({
        created => {
          new => superhashof({
            id => jstr(),
          }),
        },
      }),
      "isTruncated/isEncodingProblem omitted succeeds",
    );
  };

  subtest "explicit false" => sub {
    $tester->request_ok(
      [
        "Email/set" => {
          create => {
            new => {
              mailboxIds => { $mbox->id => \1, },
              bodyStructure => {
                partId => 'text',
                type   => 'text/plain',
              },
              bodyValues => {
                text => {
                  value             => 'email',
                  isTruncated       => jfalse,
                  isEncodingProblem => jfalse,
                },
              },
            },
          },
        },
      ],
      superhashof({
        created => {
          new => superhashof({
            id => jstr(),
          }),
        },
      }),
      "isTruncated/isEncodingProblem explicit false succeeds",
    );
  };

  subtest "explicit null" => sub {
    # XXX - Should this pass or fail? Currently passes
    # -- alh, 2018-08-29
    $tester->request_ok(
      [
        "Email/set" => {
          create => {
            new => {
              mailboxIds => { $mbox->id => \1, },
              bodyStructure => {
                partId => 'text',
                type   => 'text/plain',
              },
              bodyValues => {
                text => {
                  value             => 'email',
                  isTruncated       => undef,
                  isEncodingProblem => undef,
                },
              },
            },
          },
        },
      ],
      superhashof({
        created => {
          new => superhashof({
            id => jstr(),
          }),
        },
      }),
      "isTruncated/isEncodingProblem explicit false succeeds",
    );
  };

  subtest "explicit true" => sub {
    $tester->request_ok(
      [
        "Email/set" => {
          create => {
            new => {
              mailboxIds => { $mbox->id => \1, },
              bodyStructure => {
                partId => 'text',
                type   => 'text/plain',
              },
              bodyValues => {
                text => {
                  value             => 'email',
                  isTruncated       => jtrue,
                  isEncodingProblem => jtrue,
                },
              },
            },
          },
        },
      ],
      superhashof({
        notCreated => {
          new => {
            type => 'invalidProperties',
            properties => bag(qw(
              bodyValues/text/isEncodingProblem
              bodyValues/text/isTruncated
            )),
          },
        },
      }),
      "isTruncated/isEncodingProblem explicit true fails",
    );
  };
};
