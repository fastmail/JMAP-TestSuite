use jmaptest;
use utf8;

my ($account, $tester, $mbox);

test {
  my ($self) = @_;

  subtest "normal cannot provide a list" => sub {
    $self->create_and_check_header(
      set          => [ "header:foo" => [ qw(cat dog bird) ], ],
      expect_error => 1,
    );
  };

  subtest ":all suffix can provide a list" => sub {
    $self->create_and_check_header(
      set    => [ "header:foo:all" => [ qw(cat dog mouse) ], ],
      expect => [ ' cat', ' dog', ' mouse' ],
    );
  };

  subtest "asText" => sub {
    my @hlist = qw(
      subject
      comment
      list-id
      X-Foo
    );

    for my $header (@hlist) {
      $self->create_and_check_header(
        set    => [ "header:$header:asText" => "howdy" ],
        expect => [ ' howdy' ],
      );
    }
  };

  subtest "asAddresses" => sub {
    TODO: {
      local $TODO = "https://github.com/cyrusimap/cyrus-imapd/issues/2316"
        if $self->server->isa('JMAP::TestSuite::ServerAdapter::Cyrus');

      my $name = "Foo bar";
      my $email = "foos$$\@example.net";

      my $to_value = qq{"$name" <$email>};

      my $as_addresses = {
        name  => $name,
        email => $email,
      };

      my @hlist = qw(
        Sender
        Reply-To
        Cc
        Bcc
        Resent-From
        Resent-Sender
        Resent-Reply-To
        Resent-To
        Resent-Cc
        Resent-Bcc
        X-Foo
      );
 
      for my $header (@hlist) {
        $self->create_and_check_header(
          set    => [ "header:$header:asAddresses" => [ $as_addresses ] ],
          expect => [ " $to_value" ],
        );
      }
    }
  };

  subtest "asMessageIds" => sub {
    my @hlist = qw(
      Message-ID
      In-Reply-To
      Resent-Message-ID
      X-Foo
    );

    my $mid1 = 'foo@example.com';
    my $to_value = "<$mid1>";

    for my $header (@hlist) {
      $self->create_and_check_header(
        set    => [ "header:$header:asMessageIds" => [ "$mid1" ], ],
        expect => [ " $to_value" ],
      );
    }
  };

  subtest "asDate" => sub {
    my $value = "1969-02-14T12:02:00Z";

    my @allowed = (
      re('^\s+Sat, 15 Feb 1969'),
      re('^\s+Fri, 14 Feb 1969'),
      re('^\s+Thu, 13 Feb 1969'),
   );

    my @hlist = qw(
      Date
      Resent-Date
      X-Foo
    );

    for my $header (@hlist) {
      $self->create_and_check_header(
        set    => [ "header:$header:asDate" => $value, ],
        expect => [ any(@allowed) ],
      );
    }
  };

  subtest "asURLs" => sub {
    my $url1 = "http://example.net";
    my $url2 = "http://example.org/" . ("a" x 35);

    my $to_value = "<$url1>,\r\n <$url2>";

    my @hlist = qw(
      List-Help
      List-Unsubscribe
      List-Subscribe
      List-Post
      List-Owner
      List-Archive
      X-Foo
    );

    for my $header (@hlist) {
      $self->create_and_check_header(
        set    => [ "header:$header:asURLs" => [ $url1, $url2 ], ],
        expect => [ " $to_value" ],
      );
    }
  };
};

sub create_and_check_header {
  my ($self, %arg) = @_;

  my ($header, $val) = @{ $arg{set} };
  my $expect = $arg{expect};
  my $expect_error = $arg{expect_error};

  $account ||= $self->any_account;
  $tester  ||= $account->tester;
  $mbox    ||= $account->create_mailbox;

  my ($header_name) = $header =~ /^header:(.*?)(:|$)/;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my $want;

  if ($expect_error) {
    $want = superhashof({
      notCreated => {
        new => {
          type => 'invalidProperties',
          properties => [
            "header:$header_name",
          ],
        },
      },
    });
  } else {
    $want = superhashof({
      created => {
        new => {
          id       => jstr(),
          size     => jnum(),
          blobId   => jstr(),
          threadId => jstr(),
        },
      },
    });
  }

  my ($create) = $tester->request_ok(
    [
      "Email/set" => {
        create => {
          new => {
            mailboxIds => { $mbox->id => jtrue },
            $header => $val,
            textBody => [
              {
                partId  => 'text',
              },
            ],
            bodyValues => {
              text => {
                value => 'this is a text part',
              }
            },
          },
        },
      },
    ],
    $want,
    "Email/set create with $header"
  );

  return if $expect_error;

  my $new = $create->sentence(0)->arguments->{created}{new};
  my $id = $new->{id};
  ok($id, 'got the id');

  $tester->request_ok(
    [
      "Email/get" => {
        ids => [ $id ],
        properties => [ "header:$header_name:asRaw:all" ],
      },
    ],
    superhashof({
      list => [
        superhashof({
          "header:$header_name:asRaw:all" => $expect,
        }),
      ],
    }),
    "Email/set create with $header works as expected"
  );
}
