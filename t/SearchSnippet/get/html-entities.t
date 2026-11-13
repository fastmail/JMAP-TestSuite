use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $token = "zentity$$";

  my $email = $account->create_mailbox->add_message({
    subject => "Tom & Jerry <$token> a>b",
    body    => "Fish & chips <$token> x<y and more",
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

  my $snippet = $res->single_sentence("SearchSnippet/get")->arguments->{list}[0];

  # RFC 8621 S5: "&", "<" and ">" "MUST be replaced by an appropriate HTML
  # entity"; the only markup left is the <mark></mark> highlighting.
  for my $property (qw(subject preview)) {
    my $value = $snippet->{$property};
    unless (defined $value) {
      note("$property is null; nothing to check");
      next;
    }

    (my $text = $value) =~ s{</?mark>}{}g;
    unlike($text, qr{[<>]}, "$property has no bare < or >");
    unlike($text, qr{&(?!(?:[A-Za-z][A-Za-z0-9]*|#[0-9]+|#[xX][0-9A-Fa-f]+);)},
      "every & in $property starts an entity");
  }

  # RFC 8621 S5: the subject snippet is the whole subject, so its "&" is
  # there as an entity; the preview is "server defined" and may omit it.
  like($snippet->{subject}, qr{&amp;|&#0*38;|&#[xX]0*26;}, "the & in subject is escaped")
    if defined $snippet->{subject};
};
