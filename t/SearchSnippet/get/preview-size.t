use jmaptest;
use utf8;

use Encode ();

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $token = "zpreview$$";

  # Multi-octet characters and many matches, so a snippet counted in
  # characters, or with its <mark> tags left out of the count, overruns.
  my $email = $account->create_mailbox->add_message({
    subject  => "long preview $$",
    body_str => join(' ', map {; "☃☃☃ $token é&<>" } 1 .. 200),
    attributes => {
      content_type => 'text/plain',
      charset      => 'UTF-8',
      encoding     => 'quoted-printable',
    },
  });

  # Search indexing may be asynchronous, so wait until a query finds it.
  my $indexed = 0;
  for (1 .. 30) {
    my $ids = $tester->request([[
      "Email/query" => { filter => { text => $token } },
    ]])->single_sentence("Email/query")->arguments->{ids} // [];
    if (grep { $_ eq $email->id } @$ids) { $indexed = 1; last }
    sleep 1;
  }
  ok($indexed, 'the message is searchable')
    or return note('search index never caught up');

  my $res = $tester->request([[
    "SearchSnippet/get" => {
      emailIds => [ $email->id ],
      filter   => { text => $token },
    },
  ]]);
  ok($res->is_success, "SearchSnippet/get")
    or return diag explain $res->response_payload;

  my $preview = $res->single_sentence("SearchSnippet/get")->arguments->{list}[0]{preview};
  unless (defined $preview) {
    note("preview is null; nothing to check");
    return;
  }

  # RFC 8621 S5: the preview "MUST NOT be bigger than 255 octets in size".
  my $octets = length Encode::encode('UTF-8', "$preview");
  ok($octets <= 255, "preview is $octets octets, at most 255")
    or diag explain $preview;
};
