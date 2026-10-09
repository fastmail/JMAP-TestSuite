use jmaptest;

use Time::Local qw(timegm);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $message = $account->create_mailbox->add_message({
    raw_headers => [
      'To'          => 'Ann <ann@example.net>',
      'X-Text'      => 'first',
      'Resent-Date' => 'Mon, 01 Jan 2018 00:00:00 +0000',
      'X-Mid'       => '<one@example.net>',
      'List-Post'   => '<mailto:one@example.net>',
      'X-Group'     => 'G1: g1@example.net;',
      'To'          => 'bob@example.net, Cat <cat@example.net>',
      'X-Text'      => 'second',
      'Resent-Date' => 'Tue, 02 Jan 2018 00:00:00 +0000',
      'X-Mid'       => '<two@example.net> <three@example.net>',
      'List-Post'   => '<mailto:two@example.net>',
      'X-Group'     => 'G2: g2@example.net;',
    ],
  });

  # RFC 8620 S1.4: a Date may use any offset, so compare the instant.
  my $instant = sub {
    my @want = @_;
    return code(sub {
      my ($got) = @_;
      return (0, "not a Date") unless defined $got && $got =~ m{
        \A(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(?:\.\d*[1-9])?
        (?:Z|([+-])(\d\d):(\d\d))\z
      }x;
      my $utc = timegm($6, $5, $4, $3, $2 - 1, $1)
              - ($7 ? "${7}1" * ($8 * 3600 + $9 * 60) : 0);
      return $utc == timegm(@want) || (0, "$got is the wrong instant");
    });
  };

  my $res = $tester->request([[
    "Email/get" => {
      ids        => [ $message->id ],
      properties => [ qw(
        id
        header:To:asAddresses:all
        header:X-Group:asGroupedAddresses:all
        header:X-Text:asText:all
        header:Resent-Date:asDate:all
        header:X-Mid:asMessageIds:all
        header:List-Post:asURLs:all
        header:Cc:asAddresses:all
      ) ],
    },
  ]]);
  ok($res->is_success, "Email/get")
    or diag explain $res->response_payload;

  # RFC 8621 S4.1.3: with both suffixes the value is an array of the parsed
  # form, one item per instance in message order; none gives an empty array.
  jcmp_deeply(
    $res->single_sentence("Email/get")->arguments->{list},
    [{
      id => $message->id,
      'header:To:asAddresses:all' => [
        [ { name => 'Ann', email => 'ann@example.net' } ],
        [
          { name => undef, email => 'bob@example.net' },
          { name => 'Cat', email => 'cat@example.net' },
        ],
      ],
      'header:X-Group:asGroupedAddresses:all' => [
        [ { name => 'G1', addresses => [ { name => undef, email => 'g1@example.net' } ] } ],
        [ { name => 'G2', addresses => [ { name => undef, email => 'g2@example.net' } ] } ],
      ],
      'header:X-Text:asText:all'      => [ 'first', 'second' ],
      'header:Resent-Date:asDate:all' => [
        $instant->(0, 0, 0, 1, 0, 2018),
        $instant->(0, 0, 0, 2, 0, 2018),
      ],
      'header:X-Mid:asMessageIds:all' => [
        [ 'one@example.net' ],
        [ 'two@example.net', 'three@example.net' ],
      ],
      'header:List-Post:asURLs:all' => [
        [ 'mailto:one@example.net' ],
        [ 'mailto:two@example.net' ],
      ],
      'header:Cc:asAddresses:all' => [],
    }],
    "each :as{form}:all value is an array of parsed values",
  ) or diag explain $res->as_stripped_triples;
};
