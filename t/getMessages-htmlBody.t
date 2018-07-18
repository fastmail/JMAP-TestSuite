use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  # Get us a mailbox to play with
  my $batch = $account->create_batch(mailbox => {
      x => { name => "Folder X at $^T.$$" },
  });

  batch_ok($batch);

  ok( $batch->is_entirely_successful, "created a mailbox");
  my $x = $batch->result_for('x');

  my $blob = $account->email_blob(generic => {});
  ok($blob->is_success, "our upload succeeded (" . $blob->blobId . ")");

  $batch = $account->import_messages({
    msg => { blobId => $blob, mailboxIds => { $x->id => \1 }, },
  });

  batch_ok($batch);

  ok($batch->is_entirely_successful, "we uploaded and imported messages");

  my $res = $tester->request([[
    'Email/get' => {
      ids => [ $batch->result_for('msg')->id ],
      properties => [ qw(bodyValues htmlBody textBody) ],
      fetchAllBodyValues => JSON::true,
    },
  ]]);

  my $email = $res->single_sentence->arguments->{list}[0];

  my $html_id = $email->{htmlBody}[0]{partId};
  my $text_id = $email->{textBody}[0]{partId};

  is($html_id, $text_id, 'no html-specific body part');

  is($email->{htmlBody}[0]{type}, 'text/plain', 'no html type!');

  is(
    $email->{bodyValues}{$text_id}{value},
    'This is a very simple message.',
    'text body is correct'
  ) or diag explain $res->as_stripped_triples;
};
