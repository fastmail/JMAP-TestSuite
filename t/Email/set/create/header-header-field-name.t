use jmaptest;
use utf8;

my ($account, $tester, $mbox);

test {
  my ($self) = @_;

  $account = $self->any_account;
  $tester  = $account->tester;
  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  subtest "normal cannot provide a list" => sub {
    $self->create_and_check_header(
      set          => [ "header:foo" => [ qw(cat dog bird) ], ],
      expect_error => 1,
    );
  };

  subtest ":all suffix can provide a list" => sub {
    $self->create_and_check_header(
      set    => [ "header:foo:all" => [ qw(cat dog mouse) ], ],
      get    => "header:foo:asRaw:all",
      # RFC 8621 S4.1.2.1: Raw "will typically have a leading space".
      expect => [ map {; re(qr/\A\s*\Q$_\E\z/) } qw(cat dog mouse) ],
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
        expect => [ 'howdy' ],
      );
    }
  };

  subtest "asAddresses" => sub {
    TODO: {
      local $TODO = "https://github.com/cyrusimap/cyrus-imapd/issues/2316"
        if $self->server->isa('JMAP::TestSuite::ServerAdapter::Cyrus');

      my $name = "Foo bar";
      my $email = "foos$$\@example.net";

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
          expect => [ [ $as_addresses ] ],
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

    for my $header (@hlist) {
      $self->create_and_check_header(
        set    => [ "header:$header:asMessageIds" => [ "$mid1" ], ],
        expect => [ [ $mid1 ] ],
      );
    }
  };

  subtest "asDate" => sub {
    my $value = "1969-02-14T12:02:00Z";

    # RFC 8620 S1.4: a Date may carry any offset, so compare the instant.
    my $same_instant = code(sub {
      my $got = rfc3339_epoch($_[0]);
      return defined $got && $got == rfc3339_epoch($value);
    });

    my @hlist = qw(
      Date
      Resent-Date
      X-Foo
    );

    for my $header (@hlist) {
      $self->create_and_check_header(
        set    => [ "header:$header:asDate" => $value, ],
        expect => [ $same_instant ],
      );
    }
  };

  subtest "asURLs" => sub {
    my $url1 = "http://example.net";
    my $url2 = "http://example.org/" . ("a" x 35);

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
        expect => [ [ $url1, $url2 ] ],
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
  my $get_prop = $arg{get} // ($header =~ /:all\z/ ? $header : "$header:all");

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my $want;

  if ($expect_error) {
    $want = superhashof({
      notCreated => {
        new => invalid_properties("header:$header_name"),
      },
    });
  } else {
    $want = superhashof({
      created => {
        new => superhashof({
          id       => jstr(),
          size     => jnum(),
          blobId   => jstr(),
          threadId => jstr(),
        }),
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
        properties => [ $get_prop ],
      },
    ],
    superhashof({
      list => [
        superhashof({
          $get_prop => $expect,
        }),
      ],
    }),
    "Email/set create with $header works as expected"
  );
}

sub rfc3339_epoch {
  my ($date) = @_;
  return undef unless defined $date && $date =~ /\A
    (\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(?:\.\d+)?
    (?: Z | ([+-])(\d\d):(\d\d) )
  \z/x;

  require Time::Local;
  my $epoch = Time::Local::timegm($6, $5, $4, $3, $2 - 1, $1);
  my $offset = defined $7 ? ($8 * 3600 + $9 * 60) * ($7 eq '-' ? -1 : 1) : 0;
  return $epoch - $offset;
}
