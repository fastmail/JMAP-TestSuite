use jmaptest;

use JMAP::TestSuite::Util qw(cpart cmultipart);
use Email::MIME;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  # Inline media in both alternatives, so that the RFC 8621 S4.1.4
  # suggested algorithm puts it in textBody and htmlBody.
  my $email = cmultipart("alternative", [
    cmultipart("mixed", [
      cpart("text/plain", "plain text"),
      cpart("image/jpeg", "jpeg data"),
    ]),
    cmultipart("mixed", [
      cpart("text/html", "<p>html text</p>"),
      cpart("image/png", "png data"),
    ]),
  ]);

  my $message = $account->create_mailbox->add_message({
    email_type => 'provided',
    email      => $email->as_string,
  });

  # RFC 8621 S4.2: these include "any "text/*" part" of the list, and S4.1.4
  # says bodyValues only ever holds "text/*" parts, so media gets no value.
  for my $test (
    [ fetchTextBodyValues => 'textBody' ],
    [ fetchHTMLBodyValues => 'htmlBody' ],
  ) {
    my ($arg, $list) = @$test;

    subtest $arg => sub {
      my $res = $tester->request([[
        "Email/get" => {
          ids            => [ $message->id ],
          properties     => [ $list, 'bodyValues' ],
          bodyProperties => [ 'partId', 'type' ],
          $arg           => jtrue(),
        },
      ]]);
      ok($res->is_success, "Email/get")
        or diag explain $res->response_payload;

      my $got = $res->single_sentence("Email/get")->arguments->{list}[0];
      my @parts = @{ $got->{$list} || [] };

      my @text  = grep {;   $_->{type} =~ m{\Atext/}i } @parts;
      my @other = grep {; $_->{type} !~ m{\Atext/}i } @parts;
      ok(@text, "$list has a text part") or diag explain $got;
      note("$list holds no media part, so there is nothing to exclude")
        unless @other;

      is(
        join(q{ }, sort keys %{ $got->{bodyValues} || {} }),
        join(q{ }, sort map {; "$_->{partId}" } @text),
        "bodyValues holds exactly the text/* parts of $list",
      ) or diag explain $got;
    };
  }
};
