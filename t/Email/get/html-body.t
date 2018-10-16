use jmaptest;

use JMAP::TestSuite::Util qw(get_parts multipart);
use Path::Tiny qw(path);
use Email::MIME;

my %PART = get_parts();

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;

  my $message = $mbox->add_message({
    email_type => 'provided',
    email      => path("t/corpus/emails/structured.eml")->slurp,
  });

  my $res = $tester->request([[
    "Email/get" => {
      ids        => [ $message->id ],
      properties => [ 'htmlBody', 'bodyValues', ],
      fetchHTMLBodyValues => jtrue(),
    },
  ]]);
  ok($res->is_success, "Email/get")
    or diag explain $res->response_payload;

  my $get = $res->sentence_named("Email/get");
  my $html_body = $get->arguments->{list}[0]{htmlBody};
  my $body_values = $get->arguments->{list}[0]{bodyValues};

  ok($html_body, 'got our htmlBody');

  is(@$html_body, 3, 'got 3 parts');

  subtest "order of parts is correct and includes expected parts" => sub {
    # Ensure we got parts A, E, and K
    my @got;

    for my $part (@$html_body) {
      if ($part->{type} eq 'text/plain' || $part->{type} eq 'text/html') {
        push @got, $body_values->{$part->{partId}}->{value};
      } else {
        fail("Unknown type?! $part->{type}");
      }
    }

    jcmp_deeply(
      \@got,
      [
        "This is text part A\n",
        "<html><body> This is html part E </body></html>\n",
        "This is text part K\n",
      ],
      "htmlBody gives us correct parts in order"
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "htmlBody attributes are as expected" => sub {
    jcmp_deeply(
      $html_body,
      [ @PART{ qw(A E K) } ],
      "htmlBody parts look right"
    ) or diag explain $res->as_stripped_triples;
  };
};
