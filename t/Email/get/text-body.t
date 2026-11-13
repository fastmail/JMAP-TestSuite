use jmaptest;

use JMAP::TestSuite::Util qw(body_lists_ok get_parts multipart);
use Path::Tiny qw(path);
use Email::MIME;
use Digest::MD5 qw(md5_hex);

my %PART = get_parts();

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mbox = $account->create_mailbox;

  my $message = $mbox->add_message({
    email_type => 'provided',
    email      => path("t/corpus/emails/structured.eml")->slurp,
  });

  my $res = $tester->request([[
    "Email/get" => {
      ids        => [ $message->id ],
      properties => [ qw(bodyStructure textBody htmlBody attachments bodyValues) ],
      fetchTextBodyValues => jtrue(),
    },
  ]]);
  ok($res->is_success, "Email/get")
    or diag explain $res->response_payload;

  my $email = $res->sentence_named("Email/get")->arguments->{list}[0];
  my $text_body = $email->{textBody};
  my $body_values = $email->{bodyValues};

  ok($text_body, 'got our textBody');

  my $label_for = body_lists_ok($email, {
    leaves    => [ map {; $_ => $PART{$_} } qw(A B C D E F G H J K) ],
    suggested => {
      textBody    => [qw(A B C D K)],
      htmlBody    => [qw(A E K)],
      attachments => [qw(C F G H J)],
    },
  });

  subtest "textBody parts have the right content" => sub {
    my %content = (
      A => "This is text part A\n",
      B => "This is text part B\n",
      C => "63d6f41df41023f615ceaabc4ed0db69", # md5sum of c.jpg
      D => "This is text part D\n",
      E => "<html><body> This is html part E </body></html>\n",
      F => "0d37cbbda972721297f2085af3366ee8", # md5sum of f.jpg
      G => "6c5fd754d128a276b704bbcd4b83799b", # md5sum of g.jpg
      K => "This is text part K\n",
    );

    for my $part (@$text_body) {
      my $label = $label_for->{ $part->{partId} // '' } // next;

      my $got;
      if ($part->{type} =~ m{\Atext/}i) {
        $got = $body_values->{ $part->{partId} }{value};
      } else {
        my $download_res = $tester->download({
          blobId    => $part->{blobId},
          accountId => $account->accountId,
          name      => "part.bin",
        });
        ok($download_res->is_success, "downloaded part $label") or next;
        $got = md5_hex(${ $download_res->bytes_ref });
      }

      is($got, $content{$label}, "textBody part $label has the right content");
    }
  };
};
