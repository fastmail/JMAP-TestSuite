use jmaptest;

use JMAP::TestSuite::Util qw(get_parts multipart);
use Path::Tiny qw(path);
use Email::MIME;
use Digest::MD5 qw(md5_hex);

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
      properties => [ 'textBody', 'bodyValues', ],
      fetchTextBodyValues => jtrue(),
    },
  ]]);
  ok($res->is_success, "Email/get")
    or diag explain $res->http_response->as_string;

  my $get = $res->sentence_named("Email/get");
  my $text_body = $get->arguments->{list}[0]{textBody};
  my $body_values = $get->arguments->{list}[0]{bodyValues};

  ok($text_body, 'got our textBody');

  is(@$text_body, 5, 'got 5 parts');

  subtest "order of parts is correct and includes expected parts" => sub {
    # Ensure we got text parts A, B, image part C, and
    # text parts D, K, in that order

    # XXX For now, our image doesn't have a partId.
    # but maybe this is just the spec needing updating?
    # https://github.com/cyrusimap/cyrus-imapd/issues/2402
    # -- alh, 2018-06-21
    my @got;

    for my $part (@$text_body) {
      if ($part->{type} eq 'text/plain') {
        push @got, $body_values->{$part->{partId}}->{value};
      } elsif ($part->{type} eq 'image/jpeg') {
        my $download_res = $tester->download({
          blobId    => $part->{blobId},
          accountId => $account->accountId,
          name      => "image.jpg"
        });

        ok($download_res->is_success, 'downloaded image blob');

        push @got, md5_hex($download_res->bytes_ref);
      } else {
        fail("Unknown type?! $part->{type}");
      }
    }

    jcmp_deeply(
      \@got,
      [
        "This is text part A\n",
        "This is text part B\n",
        # md5sum of c.jpg
        "63d6f41df41023f615ceaabc4ed0db69",
        "This is text part D\n",
        "This is text part K\n",
      ],
      "textBody gives us correct parts in order"
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "textBody attributes are as expected" => sub {
    jcmp_deeply(
      $text_body,
      [ @PART{ qw(A B C D K) } ],
      "textBody parts look right"
    ) or diag explain $res->as_stripped_triples;
  };
};
