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
      properties => [ qw(
        bodyStructure
        bodyValues
        attachments
        hasAttachment
      ) ],
      fetchAllBodyValues => jtrue(),
    },
  ]]);
  ok($res->is_success, "Email/get")
    or diag explain $res->response_payload;

  my $get = $res->sentence_named("Email/get");
  my $body_structure = $get->arguments->{list}[0]{bodyStructure};
  my $body_values = $get->arguments->{list}[0]{bodyValues};

  ok($body_structure, 'got our htmlBody');

  subtest "order of parts is correct and includes expected parts" => sub {
    # Ensure we got parts A, E, and K
    my @got;

    my $extract = sub {
      my ($recurse, $part) = @_;

      if ($part->{type} eq 'text/plain' || $part->{type} eq 'text/html') {
        push @got, $body_values->{$part->{partId}}->{value};
      } elsif ($part->{type} =~ /^multipart\//) {
        $recurse->($recurse, $_) for @{ $part->{subParts} };
      } else {
        my $download_res = $tester->download({
          blobId    => $part->{blobId},
          accountId => $account->accountId,
          name      => "what.ever"
        });

        ok($download_res->is_success, 'downloaded blob');

        if ($part->{type} =~ /image/) {
          push @got, md5_hex(${ $download_res->bytes_ref });
        } else {
          push @got, ${ $download_res->bytes_ref };
        }
      }
    };

    $extract->($extract, $body_structure);

    my $rfc822_j = <<EOF;
Date: Thu, 21 Jun 2018 11:00:06 -0400
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Type: text/plain

RFC822 message
EOF

    # Download blob gives us \r\n
    $rfc822_j =~ s/\n/\r\n/g;

    jcmp_deeply(
      \@got,
      [
        "This is text part A\n",
        "This is text part B\n",
        "63d6f41df41023f615ceaabc4ed0db69", # md5sum of c.jpg
        "This is text part D\n",
        "<html><body> This is html part E </body></html>\n",
        "0d37cbbda972721297f2085af3366ee8", # md5sum of f.jpg
        "6c5fd754d128a276b704bbcd4b83799b", # md5sum og g.jpg
        "XXX Excelt H\r\n",
        $rfc822_j,
        "This is text part K\n",
      ],
      "bodyStructure gives us correct parts in order"
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "bodyStructure attributes are as expected" => sub {
    jcmp_deeply(
      $body_structure,
      multipart('mixed',
        [
          $PART{A},
          multipart('mixed',
            [
              multipart('alternative',
                [
                  multipart('mixed',
                    [ @PART{ qw(B C D) } ],
                  ),
                  multipart('related',
                    [ @PART{ qw(E F) } ],
                  ),
                ],
              ),
              @PART{ qw(G H J) },
            ],
          ),
          $PART{K},
        ],
      ),
      "bodyStructure parts look right"
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "attachments" => sub {
    jcmp_deeply(
      $get->arguments->{list}[0],
      superhashof({ hasAttachment => jtrue() }),
      'we have attachments'
    );

    my $attachments = $get->arguments->{list}[0]{attachments};

    jcmp_deeply(
      $attachments,
      [ @PART{ qw(C F G H J) } ],
      "our attachments are correct"
    );
  };
};
